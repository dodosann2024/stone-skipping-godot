extends Node3D
## 海岛打水漂 v5 — walk / run around a little tropical island, nap in the hammock, sunbathe on the
## beach towel, and skip stones from the end of the dock (standing or half-kneeling).

const GRAVITY := 9.8
const POWER_CYCLE := 1.7
const TILT_BEST := 20.0     # the stone's tilt to the water that skips best (deg)
const EL_MIN := -5.0        # launch elevation range (deg)
const EL_MAX := 30.0
const TILT_MAX := 45.0
const AIM_LIM := 1.4        # aim at most this far (rad) either side of straight out from the dock
const SWIPE_DEAD := 0.04    # swipe length (x the short screen side) that does nothing yet
const SWIPE_FULL := 0.42    # ... and the extra length for full power
const KEY_SPIN := 0.8       # keyboard throws: a decent flick
const TWIST_MAX := 0.5      # chest ahead of the hips while aiming (rad)
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
var aim_pitch := 4.0        # launch elevation (deg)
var aim_tilt := 20.0        # the stone's tilt to the water (deg)
var aim_src := "script"     # swipe | key | script (demos, tests)
var yaw_at_press := 0.0
var swipe_hist: Array = []  # [time, position] of the finger while swiping
var swipe_d := Vector2.ZERO
var throw_spin := 0.8
var key_angles := Vector2.ZERO
var cam_aim_yaw := 0.0      # the aiming camera's heading
var view_at_press := 0.0    # its heading when the finger went down: swipe angles are read against it
var swipe_move_frame := 0
var stone_tilt := 20.0
var launch_spin_v := 0.8
var first_entry := -1.0
var spin_ang := 0.0
var last_tip := ""
var el_slider: AngleSlider
var tilt_slider: AngleSlider
var throw_pad: ThrowPad
var preview_ring: MeshInstance3D

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
## Drag deltas accumulated across input events; applied once per render frame (ProMotion-safe).
var orbit_pending := Vector2.ZERO
var zoom_pending := 1.0
var touches := {}
var pinch_d := 0.0
var mouse_drag := false
var dragging := false
var demo_cam := false
var demo_nocut := false   # showcase stills of a prop: no see-through cut-out towards the boy
var ex_yaw := 0.0
# slightly telephoto follow camera, pitched down enough to see eyes + smile under the hat brim
var ex_pitch := 0.26
var ex_dist := 4.5
var last_drag := -10.0
## Fixed camera: stays put; user orbits / zooms manually. Follow = current behaviour.
var cam_fixed := false
var fix_yaw := 0.4
var fix_pitch := 0.35
var fix_dist := 6.0
var fix_target := Vector3.ZERO
var cam_mode_btn: Button
var zoom_in_btn: Button
var zoom_out_btn: Button

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
## When true, _rest_tick holds pose (shot scripts pose manually without advancing phases).
var rest_frozen := false
var rest_t := 0.0
var rest_approach := Vector3.ZERO
var rest_seat := Vector3.ZERO
var rest_lie := Vector3.ZERO
var rest_sit_b := Basis.IDENTITY
var rest_lie_b := Basis.IDENTITY
var rest_root_sit := Vector3.ZERO
var rest_side := Vector3.ZERO
var rest_cam_yaw := INF
var rest_cam_pitch := 0.2
var rest_cam_dist := 2.8
## 0..1 ease onto the sit/sleep framing (~0.8 s).
var rest_cam_ease := 0.0
## After exit, ease explore-follow from the last rest framing.
var rest_exit_cam_t := 0.0
## True if the player dragged the camera this rest-touch (tap-without-drag still wakes).
var rest_touch_dragged := false
var seat_i := -1   # island.seats entry near the kid / being sat on
var seat_face := Vector3.FORWARD   # the way he sits on it (logs: whichever side he came from)
var seat_ap := Vector3.ZERO
var seat_lying := false   # lying back along the bench / log
var lie_btn: Button
var swing_amp := 0.0
var zzz: Label3D
## Authored Blender sit/hammock clips (alignment.json) — no procedural pose.
var rest_align: Dictionary = {}
var rest_prop_xf := Transform3D.IDENTITY
var rest_clip_prop := ""  # "bench" | "log" | "hammock"
var rest_clip_phase := ""  # "enter" | "idle" | "exit"
var rest_use_clips := false
var rest_exit_xf := Transform3D.IDENTITY

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
var face_cam_tgt := Vector3.INF   # v21 face video: smoothed head target
var saved_night := false
var settle_t := 1.0
var night_btn: Button
var night_fx: NightFx
var night_amb: AudioStreamPlayer
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var mq = preload("res://mobile_quality.gd").new()
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
	# After boy (priority 10): move then camera so follow uses the same-frame pose.
	process_priority = 20
	is_web = OS.has_feature("web")
	RenderingServer.set_default_clear_color(Color(0.02, 0.05, 0.08))
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
	_load_cam_fixed()
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
	if "--walkmetrics" in args:
		_walk_metrics_report()
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
	# First paint: face the Tripo boy (3/4-front). Later _place()/walk snaps back to follow-behind.
	_snap_explore_cam(true)
	if is_web and _opt("hatprobe") == "1":
		RenderingServer.frame_pre_draw.connect(_hat_probe_tick)
		_hat_probe_place.call_deferred(_opt("at"))
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
	# start on the beach near the dock, facing the pier — camera sits on the open-sand side
	var sp := Vector3(1.35, 0, island.dock_start_z + 4.0)
	sp.y = _surface(sp.x, sp.z)
	boy.position = sp
	face_yaw = -0.35
	boy.rotation.y = face_yaw
	ground_y = sp.y
	# Default view: 3/4-front so the Tripo face is readable (drag still orbits 360°)
	ex_yaw = face_yaw + PI + 0.45
	ex_pitch = 0.22
	ex_dist = 4.0
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
	# Keep ambient modest so the boy keeps concept_A saturation (vest red, peach skin).
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 3.2
	# Full saturation — the old pastel grade (sat 0.85) washed vest/skin/hat into chalky pinks.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.02
	env.adjustment_brightness = 0.98
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
	sun.shadow_blur = 2.8
	# slight sun disk — soft enough for the brim, not so wide that the boy goes flat/pastel
	sun.light_angular_distance = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	if is_web or _opt("mobile") == "1":
		# phones: one cascade, shorter range, softer filter (blocky shadows were the day-path complaint)
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 32.0
		sun.shadow_blur = 3.6
		sun.shadow_bias = 0.045
		sun.shadow_normal_bias = 1.7
		sun.directional_shadow_pancake_size = 4.0
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 55.0
	# Slightly larger near plane avoids bush-card z-fight filling the lens on phones.
	camera.near = 0.18
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
	for i in 30:
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
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42; tm.outer_radius = 0.56; tm.rings = 24; tm.ring_segments = 4
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_ring = MeshInstance3D.new()
	preview_ring.mesh = tm
	preview_ring.scale = Vector3(1.0, 0.25, 1.0)
	preview_ring.material_override = rm
	preview_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview_ring.layers = 1 | WaterReflection.SKIP_LAYER
	preview_ring.visible = false
	add_child(preview_ring)

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
			# Slightly less opaque — over the lighthouse climb the old 0.82 white pills
			# fused with the tower into one "ghost panel" on iPhone Safari.
			sb.bg_color = Color(1, 1, 1, 0.72) if st_name != "pressed" else Color(0.85, 0.95, 1, 0.90)
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

	throw_pad = ThrowPad.new()
	throw_pad.font = ui_font
	throw_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	throw_pad.visible = false
	root.add_child(throw_pad)
	el_slider = _angle_slider("仰角", "el", EL_MIN, EL_MAX, aim_pitch, Vector2(0, 10))
	tilt_slider = _angle_slider("倾角", "tilt", 0.0, TILT_MAX, aim_tilt, Vector2(15, 25))
	el_slider.changed.connect(func(v: float) -> void: aim_pitch = v)
	tilt_slider.changed.connect(func(v: float) -> void: aim_tilt = v)

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
	cam_mode_btn = _btn("固定视角", 22)
	cam_mode_btn.custom_minimum_size = Vector2(162, 50)
	cam_mode_btn.pressed.connect(_toggle_cam_fixed)
	right_box.add_child(cam_mode_btn)
	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 8)
	zoom_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_box.add_child(zoom_row)
	zoom_out_btn = _btn("−", 28)
	zoom_out_btn.custom_minimum_size = Vector2(74, 48)
	zoom_out_btn.pressed.connect(func() -> void: _nudge_zoom(1.0 / 0.85))
	zoom_row.add_child(zoom_out_btn)
	zoom_in_btn = _btn("+", 28)
	zoom_in_btn.custom_minimum_size = Vector2(74, 48)
	zoom_in_btn.pressed.connect(func() -> void: _nudge_zoom(0.85))
	zoom_row.add_child(zoom_in_btn)
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
	right_box.resized.connect(_layout_ui)
	_layout_ui()

func _angle_slider(t: String, k: String, lo: float, hi: float, v: float, band: Vector2) -> AngleSlider:
	var s := AngleSlider.new()
	s.title = t
	s.kind = k
	s.vmin = lo
	s.vmax = hi
	s.value = v
	s.band = band
	s.font = ui_font
	s.anchor_left = 1.0; s.anchor_right = 1.0; s.anchor_top = 1.0; s.anchor_bottom = 1.0
	s.visible = false
	ui_root.add_child(s)
	return s

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
	# (portrait: the tip spans most of the 720 units across, so it starts below the button column)
	tip_box.offset_top = maxf((170.0 if tall else 120.0) + st, right_box.offset_top + right_box.size.y + 16.0) if tall else 120.0 + st
	# throw mode: the two angle sliders bottom right, the stone pad bottom centre (both above the hint)
	var sw := 92.0
	var sh := 320.0 if tall else 250.0
	var lift := (150.0 if tall else 112.0) + sb
	for i in 2:
		var s: AngleSlider = tilt_slider if i == 0 else el_slider
		s.offset_right = -14.0 - sr - i * (sw + 12.0)
		s.offset_left = s.offset_right - sw
		s.offset_bottom = -lift
		s.offset_top = -lift - sh
	var vs := get_viewport().get_visible_rect().size
	throw_pad.pad_r = 54.0 if tall else 50.0
	throw_pad.pad_c = Vector2((vs.x + sl - sr) * 0.5, vs.y - lift - throw_pad.pad_r + (24.0 if tall else 4.0))
	throw_pad.queue_redraw()

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
	if cam_mode_btn:
		# Label is the mode you switch TO (same pattern as 白天/夜晚).
		cam_mode_btn.text = "跟随视角" if cam_fixed else "固定视角"
		cam_mode_btn.visible = mode == Mode.EXPLORE or mode == Mode.REST or mode == Mode.VIEW
	if zoom_in_btn and zoom_out_btn:
		var show_zoom := cam_fixed and (mode == Mode.EXPLORE or mode == Mode.REST or mode == Mode.VIEW)
		zoom_in_btn.get_parent().visible = show_zoom
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
					if last_tip != "":
						lbl_hint.text = last_tip
					elif _tall():
						lbl_hint.text = "按住石头往海面划：方向 = 瞄准，越长越用力\n松手时顺势一甩 = 旋转 · 右边调仰角和倾角"
					else:
						lbl_hint.text = "按住石头往海面划：方向 = 瞄准，越长越用力，松手时顺势一甩 = 旋转\n右边调出手仰角和石头倾角（20° 最好）· 键盘：←→ 瞄准  ↑↓ 仰角  Q/E 倾角  按住空格蓄力"
				State.AIMING:
					lbl_hint.text = {"swipe": "松手扔出 · 往回拉取消", "key": "看准力度条，松开空格投出！"}.get(aim_src, "看准力度条，松手投出！")
				_:
					lbl_hint.text = ""
	power_box.visible = state == State.AIMING and throw_mode
	power_bar.visible = aim_src != "swipe"

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
		var lp: Vector3 = island.lounger_seat_point(0.5)["pos"]
		if Vector2(p.x - tp.x, p.z - tp.z).length() < 1.7 \
				or Vector2(p.x - lp.x, p.z - lp.z).length() < 1.6:
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
	cam_aim_yaw = aim_yaw
	_toast("打水漂！按住石头往海面划", 1.8)
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
	_hide_preview()
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
		if not boy.settling() and settle_t <= 0.0:
			boy.begin_settle(0.38)
		if boy.settling():
			settle_t += delta
			target_v = Vector3(-sin(face_yaw), 0, -cos(face_yaw)) * 0.45
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
	# Soft accel so screen-space boy delta stays even during walk/run ramp (max/med < 2).
	var acc := (2.2 if s < WALK_MAX else 1.6) if spd_t > s else 6.0
	s = move_toward(s, spd_t, acc * delta)
	move_vel = Vector3(-sin(face_yaw), 0, -cos(face_yaw)) * s
	var from := player.position
	var wish_step := move_vel * delta
	var to := _try_move(from, wish_step)
	# Cap per-frame lateral shove from wall slide (lighthouse / rock first contact). A sudden
	# sideways pop reads as a multi-pixel screen spike even when the spring-arm is smooth.
	var step := to - from
	step.y = 0.0
	if wish_step.length_squared() > 1e-8 and step.length_squared() > 1e-8:
		var along := wish_step.normalized()
		var lat := step - along * step.dot(along)
		var max_lat := maxf(wish_step.length() * 0.45, 0.012)
		if lat.length() > max_lat:
			to = from + along * step.dot(along) + lat.limit_length(max_lat)
			# Re-resolve so the capped slide doesn't re-penetrate.
			to = _try_move(from, to - from)
	var real := (to - from) / maxf(delta, 1e-4)
	real.y = 0.0
	if real.length() < move_vel.length() * 0.5:
		# Frame-rate independent collision bleed (was constant 0.5 → jitter at 120Hz).
		move_vel = move_vel.lerp(real, 1.0 - exp(-delta * 14.0))
	cur_speed = real.length()
	var h := _surface(to.x, to.z)
	ground_y = h if absf(h - ground_y) > 0.5 else lerpf(ground_y, h, 1.0 - exp(-delta * 18.0))
	to.y = ground_y
	player.position = to
	player.rotation.y = face_yaw
	wading = not _on_dock(to.x, to.z) and h < -0.03
	boy.wading = wading
	boy.pivoting = spot_turning
	boy.turn_ahead = wrapf(spot_goal - face_yaw, -PI, PI) if spot_turning else (wrapf(wish_yaw - face_yaw, -PI, PI) if mag > 0.05 else 0.0)
	boy.turn_lean = lerpf(boy.turn_lean, clampf(boy.turn_ahead, -0.7, 0.7), 1.0 - exp(-delta * 5.0))
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

func _ensure_rest_align() -> void:
	if not rest_align.is_empty():
		return
	var path := "res://props/alignment.json"
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		rest_align = parsed


func _begin_rest(kind: String) -> void:
	mode = Mode.REST
	rest_kind = kind
	rest_phase = 0
	rest_t = 0.0
	rest_cam_yaw = INF
	rest_cam_pitch = 0.2
	rest_cam_dist = 2.8
	rest_cam_ease = 0.0
	rest_exit_cam_t = 0.0
	rest_touch_dragged = false
	move_vel = Vector3.ZERO
	rest_use_clips = false
	rest_clip_phase = ""
	rest_clip_prop = ""
	set_meta("lie_snapped", false)
	set_meta("lie_mesh_nudged", false)
	set_meta("fix_rest_locked", false)
	_ensure_rest_align()
	# Prefer authored Blender clips for bench / log / hammock.
	if kind == "sleep" and boy.ap and boy.ap.has_animation("hammock_enter"):
		rest_use_clips = true
		rest_clip_prop = "hammock"
		_setup_hammock_clip_rest()
	elif kind == "seat" and seat_i >= 0 and seat_i < island.seats.size():
		var st0: Dictionary = island.seats[seat_i]
		var nm := String(st0.get("name", ""))
		if nm == "长椅" and boy.ap and boy.ap.has_animation("bench_sit_enter"):
			rest_use_clips = true
			rest_clip_prop = "bench"
			_setup_seat_clip_rest(st0)
		elif nm == "坐木" and boy.ap and boy.ap.has_animation("log_sit_enter"):
			rest_use_clips = true
			rest_clip_prop = "log"
			_setup_seat_clip_rest(st0)
	if rest_use_clips:
		boy.end_activity()
		boy.set_hat_mode("head")
		if kind == "sleep":
			island.set_hammock_clip_frame("empty", 0)
		boy.rotation = Vector3(0, face_yaw, 0)
		_update_ui()
		return
	# Legacy procedural path (lounger / missing clips).
	if kind == "sleep":
		_setup_hammock_rest()
	elif kind == "seat":
		var st: Dictionary = island.seats[seat_i]
		var face: Vector3 = seat_face.normalized()
		seat_lying = false
		rest_side = face.cross(Vector3.UP).normalized()
		rest_sit_b = Basis(Vector3.UP, atan2(-face.x, -face.z))
		rest_approach = seat_ap
		var pl0 := boy.activity("seat", 1.0, 0.0, 0.0)
		var top: Vector3 = st["top"]
		rest_seat = top + Vector3(0, pl0.y - Island.SEAT_TOP, 0)
		rest_lie = top + Vector3(0, LIE_BACK, 0) - rest_side * 0.1
		rest_lie_b = _lie_basis(rest_side)
	else:
		_setup_lounger_rest()
	rest_approach.y = _surface(rest_approach.x, rest_approach.z)
	var pl := boy.activity(kind, 1.0, 0.0, 0.0)
	rest_root_sit = rest_seat - rest_sit_b * pl
	if kind == "seat" or kind == "sleep":
		boy.global_transform = Transform3D(rest_sit_b, rest_root_sit)
		for _s in 12:
			_snap_sit_contact()
			pl = boy.activity(kind, 1.0, 0.0, 0.0)
			rest_root_sit = rest_seat - rest_sit_b * pl
			boy.global_transform = Transform3D(rest_sit_b, rest_root_sit)
	boy.end_activity()
	if kind == "sleep":
		island.set_hammock_load([] as Array[Vector3])
	boy.rotation = Vector3(0, face_yaw, 0)
	_update_ui()


func _setup_seat_clip_rest(st: Dictionary) -> void:
	seat_lying = false
	var face: Vector3 = seat_face.normalized()
	rest_side = face.cross(Vector3.UP).normalized()
	rest_prop_xf = st.get("prop_xf", Transform3D.IDENTITY)
	if rest_prop_xf == Transform3D.IDENTITY:
		rest_prop_xf = Transform3D(Basis(Vector3.UP, atan2(-face.x, -face.z) + PI),
			Vector3(st["top"].x, _surface(st["top"].x, st["top"].z), st["top"].z))
	rest_approach = st["approach"]
	rest_approach.y = _surface(rest_approach.x, rest_approach.z)
	rest_seat = st["top"]
	rest_sit_b = rest_prop_xf.basis
	# Clip enter starts at root_pos (0,0,-0.5) yaw 0 in prop frame (exact prop Y).
	var clip_key := "bench_sit_enter" if rest_clip_prop == "bench" else "log_sit_enter"
	var cinfo: Dictionary = rest_align.get("clips", {}).get(clip_key, {})
	var rp: Array = cinfo.get("root_pos_prop", [0, 0, -0.5])
	var local := Vector3(float(rp[0]), float(rp[1]), float(rp[2]))
	rest_root_sit = rest_prop_xf * local
	rest_approach = rest_prop_xf * Vector3(0.0, 0.0, -0.50)
	rest_approach.y = rest_prop_xf.origin.y


func _setup_hammock_clip_rest() -> void:
	rest_prop_xf = island.hammock_node.global_transform if island.hammock_node else Transform3D.IDENTITY
	hammock_prop_side()
	var cinfo: Dictionary = rest_align.get("clips", {}).get("hammock_enter", {})
	var rp: Array = cinfo.get("root_pos_prop", [0, -0.96, 0.63])
	var local := Vector3(float(rp[0]), float(rp[1]), float(rp[2]))
	rest_root_sit = rest_prop_xf * local
	# Approach = start of enter (inland side).
	rest_approach = rest_root_sit
	rest_approach.y = _surface(rest_approach.x, rest_approach.z)
	rest_seat = rest_prop_xf * Vector3(0, 0, 0)
	rest_sit_b = rest_prop_xf.basis
	rest_side = (rest_prop_xf.basis * Vector3(0, 0, 1)).normalized()


func hammock_prop_side() -> void:
	if island.hammock_node:
		rest_side = island.hammock_node.global_transform.basis.z.normalized()

const LIE_BACK := 0.085   # pelvis centre above the seat when lying on the back
const SEAT_LIE_DUR := 1.6
const LIE_BLEND_DUR := 0.6  # sun / hammock sit→lie blend
## Body half-length used to place hips/head/feet on lounger & hammock (Tripo ~0.8 m tall).
const LIE_BODY_HALF := 0.38
const LIE_CONTACT_TOL := 0.02  # 0–2 cm gap target after snap


## Hammock nap: hips at the sag centre, head/feet slightly raised; body follows the fabric curve.
func _setup_hammock_rest() -> void:
	var hs := _hammock_spot()
	var along: Vector3 = hs[1]
	var side: Vector3 = hs[2]
	rest_side = side
	var bed: Vector3 = island.hammock_point(0.5)
	# Head on the upper end, hips mid-pocket — body along the hammock centreline.
	var head_t := 0.72
	var hip_t := 0.48
	var foot_t := 0.24
	var hip_f: Dictionary = island.hammock_frame(hip_t)
	var head_f: Dictionary = island.hammock_frame(head_t)
	var foot_f: Dictionary = island.hammock_frame(foot_t)
	var head_dir: Vector3 = ((head_f["pos"] as Vector3) - (hip_f["pos"] as Vector3))
	if head_dir.length_squared() < 1e-6:
		head_dir = along
	else:
		head_dir = head_dir.normalized()
	if head_dir.dot(along) < 0.0:
		var tmp := head_t
		head_t = foot_t
		foot_t = tmp
		head_f = island.hammock_frame(head_t)
		foot_f = island.hammock_frame(foot_t)
		head_dir = ((head_f["pos"] as Vector3) - (hip_f["pos"] as Vector3)).normalized()
	# Keep the spine on the centreline (no diagonal twist into the rails).
	var into: Vector3 = (-Vector3.UP).lerp(-(hip_f["normal"] as Vector3).normalized(), 0.25).normalized()
	rest_lie_b = _lie_basis_oriented(head_dir, into)
	# Nest ~8 cm into the dish so fabric sides rise above the torso without burying him.
	var hip_pos: Vector3 = hip_f["pos"] as Vector3
	rest_lie = hip_pos - (hip_f["normal"] as Vector3) * 0.08
	# Sit facing OUT toward the approach so thighs hang over the near edge to the ground.
	rest_sit_b = Basis(Vector3.UP, atan2(-side.x, -side.z))
	var sit_frame: Dictionary = island.hammock_frame(0.50)
	var sit_n: Vector3 = (sit_frame["normal"] as Vector3).normalized()
	var sit_side: Vector3 = (sit_frame["side"] as Vector3).normalized()
	if sit_side.dot(side) < 0.0:
		sit_side = -sit_side
	rest_seat = (sit_frame["pos"] as Vector3) + sit_side * (island.hammock_half_w * 0.90) + sit_n * 0.08
	# Stand on sand beside the hammock, ≥0.6 m from any palm trunk.
	rest_approach = _hammock_stand_clear(bed, side)
	boy.hat_beside_world = Vector3.ZERO
	set_meta("lie_head_t", head_t)
	set_meta("lie_hip_t", hip_t)
	set_meta("lie_foot_t", foot_t)
	set_meta("lie_foot_pos", foot_f["pos"])


## Pick a stand pose beside the hammock that clears palm trunks by ≥ min_clear metres.
func _hammock_stand_clear(bed: Vector3, side: Vector3, min_clear := 0.6) -> Vector3:
	var candidates: Array[Vector3] = []
	for sgn in [1.0, -1.0]:
		for dist in [0.95, 1.15, 1.40, 1.70]:
			var p: Vector3 = bed + side * sgn * (island.hammock_half_w + dist)
			p.y = Island.ground_h(p.x, p.z)
			candidates.append(p)
	var best := candidates[0]
	var best_d := -1.0
	for p in candidates:
		var d := _nearest_trunk_dist(p)
		if d >= min_clear and d > best_d:
			best_d = d
			best = p
	if best_d < min_clear:
		# Nudge the better side away until clear.
		best = candidates[0]
		for _i in 16:
			var d2 := _nearest_trunk_dist(best)
			if d2 >= min_clear:
				break
			var away := _nearest_trunk_away(best)
			best += away * (min_clear - d2 + 0.08)
			best.y = Island.ground_h(best.x, best.z)
		rest_side = (best - bed).normalized()
		rest_side.y = 0.0
		if rest_side.length_squared() < 1e-6:
			rest_side = side
		else:
			rest_side = rest_side.normalized()
	return best


func _nearest_trunk_dist(p: Vector3) -> float:
	var best := 1e9
	for tr in island.trunks:
		if tr.is_empty():
			continue
		var base: Vector3 = tr[0]
		best = minf(best, Vector2(p.x - base.x, p.z - base.z).length())
	return best


func _nearest_trunk_away(p: Vector3) -> Vector3:
	var best := 1e9
	var away := Vector3.RIGHT
	for tr in island.trunks:
		if tr.is_empty():
			continue
		var base: Vector3 = tr[0]
		var d := Vector2(p.x - base.x, p.z - base.z).length()
		if d < best:
			best = d
			away = Vector3(p.x - base.x, 0.0, p.z - base.z)
	if away.length_squared() < 1e-6:
		return rest_side if rest_side.length_squared() > 1e-6 else Vector3.RIGHT
	return away.normalized()


## Sunbathing on the chaise: hips in the seat–back crease, spine+head on the ~45° pad,
## heels on the seat cushion. Hat is off (on chest / sand). Snap by skinned mesh only.
func _setup_lounger_rest() -> void:
	# Real chaise: hips on the seat just forward of the crease (butt on cushion, not in the hinge
	# corner), spine along the ~45° pad, head on the pad.
	# Hips just forward of the crease so thighs rest on the seat top (not in the hinge).
	var seat_hip_u := 0.82
	var hip_s := 0.42
	var head_s := 0.82
	var foot_s := 0.10
	var seat_h: Dictionary = island.lounger_seat_point(seat_hip_u)
	# Head mid-pad so the skull rests on cushion (reachable, not past the top rail).
	var back_h: Dictionary = island.lounger_back_point(0.62)
	var back_mid: Dictionary = island.lounger_back_point(0.42)
	var seat_along: Vector3 = (seat_h["along"] as Vector3).normalized()
	var seat_n: Vector3 = (seat_h["normal"] as Vector3).normalized()
	var back_n: Vector3 = (back_mid["normal"] as Vector3).normalized()
	# Head axis = up the backrest pad from the crease (must point toward the head end).
	var to_head: Vector3 = (back_h["pos"] as Vector3) - (seat_h["pos"] as Vector3)
	var head_dir: Vector3 = (back_h["along"] as Vector3).normalized()
	if head_dir.dot(to_head) < 0.0:
		head_dir = -head_dir
	# Prefer the pad along, but keep a little of the crease→head chord so hips stay near the hinge.
	if to_head.length_squared() > 1e-6:
		head_dir = head_dir.lerp(to_head.normalized(), 0.25).normalized()
	var side: Vector3 = seat_along.cross(Vector3.UP).normalized()
	if side.length_squared() < 1e-6:
		side = island.lounger_xf.basis.x.normalized()
	rest_side = side
	var st_i := -1
	for i in island.seats.size():
		if island.seats[i]["name"] == "躺椅":
			st_i = i
			break
	if st_i >= 0:
		rest_approach = island.seats[st_i]["approach"]
		rest_seat = island.seats[st_i]["top"] + Vector3(0, 0.05, 0)
	else:
		rest_seat = (seat_h["pos"] as Vector3) + side * 0.35
		rest_approach = rest_seat + side * 0.4
	rest_sit_b = Basis(Vector3.UP, atan2(-side.x, -side.z))
	# Into: follow the backrest so the torso lies ON the pad (not hunched forward).
	var into: Vector3 = (-back_n * 0.90 - seat_n * 0.10).normalized()
	rest_lie_b = _lie_basis_oriented(head_dir, into)
	# Guard: face (= −into after basis) must look skyward.
	if (-rest_lie_b.z).dot(Vector3.UP) < 0.50:
		into = (-back_n * 0.96 - seat_n * 0.04).normalized()
		rest_lie_b = _lie_basis_oriented(head_dir, into)
	# Start ~14 cm above foam; snap settles the back onto the pad.
	var hip_target: Vector3 = (seat_h["pos"] as Vector3) + seat_n * 0.14
	hip_target += back_n * 0.025
	rest_lie = hip_target
	set_meta("lie_head_s", head_s)
	set_meta("lie_foot_s", foot_s)
	set_meta("lie_hip_s", hip_s)
	set_meta("lie_seat_hip_u", seat_hip_u)
	set_meta("lie_foot_plane_u", 0.12)
	set_meta("lie_back_n", back_n)
	set_meta("lie_head_target", (back_h["pos"] as Vector3) + back_n * 0.04)
	# Sand beside the chaise — clearly off the body, flat on the ground (no float).
	var sand_hat: Vector3 = (island.lounger_xf.origin) + side * 1.25 + seat_along * 0.15
	sand_hat.y = Island.ground_h(sand_hat.x, sand_hat.z) + 0.015
	set_meta("lie_hat_sand", sand_hat)
	boy.hat_beside_world = sand_hat

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

## Lying on the back (supine): local +Y = head_dir, local +Z = into the bed.
## Tripo mesh faces model +Z; with model.rotation.y = PI that maps to boy −Z, so −Z (= −into)
## is the chest/face direction (sky / away from the pad).
func _lie_basis(head_dir: Vector3) -> Basis:
	return _lie_basis_oriented(head_dir, Vector3.DOWN)


## Build a supine basis from an explicit head axis and an into-the-support direction.
func _lie_basis_oriented(head_dir: Vector3, into_bed: Vector3) -> Basis:
	var y := head_dir.normalized()
	var z := into_bed - y * into_bed.dot(y)
	if z.length_squared() < 1e-8:
		z = Vector3.DOWN - y * Vector3.DOWN.dot(y)
	z = z.normalized()
	# Chest/face (= boy −Z) must have an upward component so selftest face_up passes.
	if (-z).dot(Vector3.UP) < 0.0:
		z = -z
	return Basis(y.cross(z), y, z)


## Direction from the body toward the support surface (boy +Z; chest is −Z).
func _lie_into_bed() -> Vector3:
	return rest_lie_b.z.normalized()


## Current hammock swing that maps rest-world → swung-world (identity when not sleeping).
func _lie_swing() -> Transform3D:
	if rest_kind == "sleep" and island.hammock_node:
		var mid := (island.hammock_a + island.hammock_b) * 0.5
		return island.hammock_node.global_transform * Transform3D(Basis.IDENTITY, -mid)
	return Transform3D.IDENTITY


## Raise/lower the sit root so butt + thigh mesh rests ON the seat top (sky-side positive).
## Uses skinned verts near the hips over the seat footprint — not the hip bone alone.
## Seat top Y comes from the prop entry (mesh AABB / authored surface), never a hardcoded offset alone.
func _snap_sit_contact() -> void:
	if seat_lying:
		return
	if rest_kind == "sleep":
		_snap_hammock_sit_contact()
		return
	if rest_kind != "seat" or seat_i < 0 or seat_i >= island.seats.size():
		return
	var st: Dictionary = island.seats[seat_i]
	var top: Vector3 = st["top"]
	var face: Vector3 = seat_face.normalized()
	# Iterate in-place so one call settles even when process is ticking.
	# Logs (坐木) need a wider contact cloud + more passes: short Tripo butt can
	# miss a tight hip sphere, leaving a 3–4 cm hover or a 2 cm dig from the back.
	var is_log := String(st.get("name", "")) == "坐木"
	var is_bench := String(st.get("name", "")) == "长椅"
	var passes := 12 if is_log else 10
	for _iter in passes:
		# Clear foot overrides before measuring — a prior soft-plant can stretch Tripo
		# shorts through the board and fool the deepest sample into a false dig/float.
		boy.clear_foot_plant()
		boy.activity("seat", 1.0, 0.0, gt)
		boy.global_transform = Transform3D(rest_sit_b, rest_root_sit)
		var hips: Vector3 = boy.lie_bone_world("mixamorig_Hips")
		var samples: Array[Vector3] = boy.skinned_sample_world(1200)
		var depths: Array[float] = []
		var hip_r := 0.38 if is_log else 0.30
		var lat_max := 0.70 if is_log else 0.50
		for s in samples:
			# Contact cloud: underside of butt + proximal thighs over the board.
			if s.distance_to(hips) > hip_r:
				continue
			if (s - hips).dot(face) > 0.22:
				continue
			if s.y > hips.y + 0.02:
				continue
			# Ignore Tripo shorts spike verts that hang far below the hip — they dig
			# the metric while the visible sit surface still floats.
			if hips.y - s.y > 0.11:
				continue
			var lat: float = (s - top).dot(rest_side)
			var along: float = (s - top).dot(-face)
			# Stay over the plank (bench front half); logs allow a little behind.
			if absf(lat) > lat_max or along < (-0.22 if is_log else -0.05) or along > (0.50 if is_log else 0.28):
				continue
			depths.append(s.y - top.y)
		var deepest: float
		if depths.is_empty():
			# Tripo ischia hang ~10–12 cm below the hip bone at the visual sit shell.
			deepest = (hips.y - 0.11) - top.y
		else:
			depths.sort()
			# Low percentile — ignore a few remaining spikes.
			var idx := mini(maxi(int(depths.size() * 0.15), 0), depths.size() - 1)
			deepest = depths[idx]
		# Bench: slight float so Tripo shorts don't bury through the plank; log kisses closer.
		var target := 0.012 if is_bench else 0.003
		var err := target - deepest
		if absf(err) < 0.004:
			boy.global_transform = Transform3D(rest_sit_b, rest_root_sit)
			break
		var step := clampf(err, -0.08, 0.08)
		rest_root_sit.y += step
		rest_seat.y += step
	boy.global_transform = Transform3D(rest_sit_b, rest_root_sit)
	# Gentle sole kiss / soft hang — never rubber-hose short Tripo shins through the board.
	if is_bench or is_log:
		var gnd := Vector3(rest_root_sit.x, _surface(rest_root_sit.x, rest_root_sit.z), rest_root_sit.z)
		# Short Tripo shins hang above the sand — allow a longer soft pull toward ground.
		boy.plant_feet_soft(gnd, Vector3.UP, 0.02, 0.28)


## Settle butt onto the near-edge hammock fabric while seated (legs hang outside).
func _snap_hammock_sit_contact() -> void:
	if rest_kind != "sleep":
		return
	for _iter in 8:
		boy.activity("sleep", 1.0, 0.0, gt)
		boy.global_transform = Transform3D(rest_sit_b, rest_root_sit)
		_update_hammock_load()
		var sit_frame: Dictionary = island.hammock_frame(0.50)
		var n: Vector3 = (sit_frame["normal"] as Vector3).normalized()
		if n.y < 0.2:
			n = Vector3.UP
		var sit_side: Vector3 = (sit_frame["side"] as Vector3).normalized()
		if sit_side.dot(rest_side) < 0.0:
			sit_side = -sit_side
		# Contact target = near-edge lip (matches rest_seat), not cradle centre.
		var top: Vector3 = (sit_frame["pos"] as Vector3) + sit_side * (island.hammock_half_w * 0.92)
		var hips: Vector3 = boy.lie_bone_world("mixamorig_Hips")
		var samples: Array[Vector3] = boy.skinned_sample_world(700)
		var deepest := 1e9
		var hit := false
		for s in samples:
			if s.distance_to(hips) > 0.28:
				continue
			if s.y > hips.y + 0.05:
				continue
			# Near-edge samples only (ignore hanging thighs outside the fabric).
			if (s - top).length() > 0.42:
				continue
			hit = true
			deepest = minf(deepest, (s - top).dot(n))
		if not hit:
			deepest = (hips - top).dot(n) - 0.10
		var target := 0.02
		var err := target - deepest
		if absf(err) < 0.004:
			_update_hammock_load()
			return
		var step := clampf(err, -0.05, 0.05)
		rest_root_sit += n * step
		rest_seat += n * step
	boy.global_transform = Transform3D(rest_sit_b, rest_root_sit)
	_update_hammock_load()


## After the lie pose is applied, nudge rest_lie so the skinned mesh sits on the support
## (no poke-through deeper than ~0, no large float). Includes baked hat verts.
func _snap_lie_contact() -> void:
	if rest_kind != "sun" and rest_kind != "sleep":
		return
	var into_bed: Vector3 = _lie_into_bed()
	# Skin shell toward the bed. Tiny hammock offset — large offsets made the snap
	# "settle" while the visible hip bone still floated above the fabric.
	var mesh_off := 0.04 if rest_kind == "sleep" else 0.08
	var pts: Dictionary = boy.lie_contact_points(into_bed, mesh_off)
	var swing := _lie_swing()
	# Include baked hat verts for hammock fabric; lounger uses bone snap (hat tip ~kiss).
	var mesh_d := lie_mesh_penetration_depth(true)
	if rest_kind == "sleep":
		var hip_f: Dictionary = island.hammock_frame(float(get_meta("lie_hip_t", 0.48)))
		var head_f0: Dictionary = island.hammock_frame(float(get_meta("lie_head_t", 0.68)))
		var head_w: Vector3 = boy.lie_bone_world("mixamorig_Head")
		var hip_p: Vector3 = swing * (hip_f["pos"] as Vector3)
		var head_p0: Vector3 = swing * (head_f0["pos"] as Vector3)
		var hip_side: Vector3 = (swing.basis * (hip_f["side"] as Vector3)).normalized()
		var hn0: Vector3 = (swing.basis * (hip_f["normal"] as Vector3)).normalized()
		var head_n0: Vector3 = (swing.basis * (head_f0["normal"] as Vector3)).normalized()
		if hn0.y < 0.2:
			hn0 = Vector3.UP
		# Keep hips + head on the cradle centreline.
		var hip_lat0: float = (pts["hips"] - hip_p).dot(hip_side)
		var head_lat0: float = (head_w - head_p0).dot(hip_side)
		var corr: float = 0.6 * hip_lat0 + 0.4 * head_lat0
		if absf(corr) > 0.004:
			rest_lie -= hip_side * clampf(corr, -0.16, 0.16)
		# Vertical: lift for poke-through (hat brim included); settle light floats.
		var hip_gap := _signed_gap(pts["hips"], hip_p, hn0)
		var spine_gap := _signed_gap(pts["spine"], hip_p, hn0)
		var head_gap := _signed_gap(pts["head"], head_p0, head_n0)
		var sink_gap := minf(hip_gap, minf(spine_gap, head_gap))
		# Only settle down when hips AND spine are both floating — never push a
		# penetrating hip deeper just because the spine still floats a bit.
		var both_float := hip_gap > 0.012 and spine_gap > 0.012
		var float_gap := minf(hip_gap, spine_gap)
		# Nest ~10 cm into the dish so fabric sides rise above the torso.
		const NEST := -0.08
		if sink_gap < NEST - 0.06:
			rest_lie += hn0 * minf(-(sink_gap - NEST) * 0.45, 0.08)
		elif hip_gap > NEST + 0.025 or both_float:
			rest_lie -= hn0 * minf(hip_gap - NEST, 0.16)
		if head_gap < -0.02 and hip_gap < 0.05:
			rest_lie += head_n0 * minf(-head_gap, 0.04) * 0.35
		return
	# Lounger: foam sink OK; fail only on wood-board punch. Settle hips/head onto the pads.
	# Bone snap only — hat tip may kiss foam within 1 cm; over-lifting floats the torso.
	var seat_u: float = float(get_meta("lie_seat_hip_u", 0.96))
	var hip_s: Dictionary = island.lounger_seat_point(seat_u)
	var mid_b: Dictionary = island.lounger_back_point(0.38)
	var head_b: Dictionary = island.lounger_back_point(0.62)
	var back_n: Vector3 = (mid_b["normal"] as Vector3).normalized()
	var head_n: Vector3 = (head_b["normal"] as Vector3).normalized()
	var seat_n: Vector3 = (hip_s["normal"] as Vector3).normalized()
	var seat_along: Vector3 = (hip_s["along"] as Vector3).normalized()  # toward hinge
	# Bone gaps with a skin shell. Wide mesh probes at Spine2 falsely "kiss" via butt verts
	# at the crease while the torso floats ~12 cm in front of the pad (#45 hunch look).
	var spine1_w: Vector3 = boy.lie_bone_world("mixamorig_Spine1")
	var spine2_w: Vector3 = boy.lie_bone_world("mixamorig_Spine2")
	var head_w: Vector3 = boy.lie_bone_world("mixamorig_Head")
	var hips_w: Vector3 = boy.lie_bone_world("mixamorig_Hips")
	# Skin shell so bones settle onto the pad without burying Tripo flesh.
	const SKIN_BACK := 0.045
	const SKIN_HEAD := 0.055
	const SKIN_HIP := 0.08
	var g_s2 := minf(
		_signed_gap(spine1_w, mid_b["pos"], back_n) - SKIN_BACK,
		_signed_gap(spine2_w, mid_b["pos"], back_n) - SKIN_BACK)
	var g_head := _signed_gap(head_w, head_b["pos"], head_n) - SKIN_HEAD
	var g_hip := _signed_gap(hips_w, hip_s["pos"], seat_n) - SKIN_HIP
	var move := Vector3.ZERO
	# Pull the reclined torso onto the pad. -back_n sinks into the seat — compensate.
	if g_s2 > 0.012:
		var pull := minf(g_s2 - 0.006, 0.035)
		move -= back_n * pull
		move += seat_n * pull * 0.45
	elif g_s2 < -0.01:
		move += back_n * minf(-g_s2 - 0.002, 0.04)
	if g_head > 0.012:
		var hpull := minf(g_head - 0.006, 0.035)
		move -= head_n * hpull
		move += seat_n * hpull * 0.35
		move += seat_along * minf(hpull * 0.2, 0.01)
	elif g_head < -0.01:
		move += head_n * minf(-g_head - 0.002, 0.04)
	if g_hip > 0.015:
		move -= seat_n * minf(g_hip - 0.008, 0.022)
	elif g_hip < -0.01:
		move += seat_n * minf(-g_hip - 0.002, 0.03)
	# Cap hat/body dig at ~8 mm: tip may kiss foam, but approach-angle leftovers must clear.
	if mesh_d < -0.01 and move.dot(head_n) < 0.008:
		move += head_n * minf(-mesh_d - 0.005, 0.014)
	if move.length() > 0.05:
		move = move.normalized() * 0.05
	rest_lie += move


func _signed_gap(point: Vector3, surface: Vector3, normal: Vector3) -> float:
	# positive ⇒ point is on the outward (sky) side of the surface = floating
	return (point - surface).dot(normal.normalized())


## Gaps for selftest / debug: {hips, spine, head, foot_l, foot_r} in metres (sky-side positive).
func lie_contact_gaps() -> Dictionary:
	if rest_kind != "sun" and rest_kind != "sleep":
		return {}
	var into_bed: Vector3 = _lie_into_bed()
	# Shell ≈ Tripo skin thickness so gap≈0 when the mesh kisses the support.
	var shell := 0.28 if rest_kind == "sleep" else 0.08
	var pts: Dictionary = boy.lie_contact_points(into_bed, shell)
	var swing := _lie_swing()
	var out := {}
	if rest_kind == "sleep":
		var hip_f: Dictionary = island.hammock_frame(float(get_meta("lie_hip_t", 0.48)))
		var head_f: Dictionary = island.hammock_frame(float(get_meta("lie_head_t", 0.68)))
		var foot_f: Dictionary = island.hammock_frame(float(get_meta("lie_foot_t", 0.28)))
		var hip_p: Vector3 = swing * (hip_f["pos"] as Vector3)
		var hip_n: Vector3 = (swing.basis * (hip_f["normal"] as Vector3)).normalized()
		var head_p: Vector3 = swing * (head_f["pos"] as Vector3)
		var head_n: Vector3 = (swing.basis * (head_f["normal"] as Vector3)).normalized()
		var foot_p: Vector3 = swing * (foot_f["pos"] as Vector3)
		var foot_n: Vector3 = (swing.basis * (foot_f["normal"] as Vector3)).normalized()
		out["hips"] = _signed_gap(pts["hips"], hip_p, hip_n)
		out["spine"] = _signed_gap(pts["spine"], hip_p, hip_n)
		out["head"] = _signed_gap(pts["head"], head_p, head_n)
		out["foot_l"] = _signed_gap(pts["foot_l"], foot_p, foot_n)
		out["foot_r"] = _signed_gap(pts["foot_r"], foot_p, foot_n)
	else:
		var seat_u: float = float(get_meta("lie_seat_hip_u", 0.96))
		var hip_s: Dictionary = island.lounger_seat_point(seat_u)
		var foot_s: Dictionary = island.lounger_seat_point(float(get_meta("lie_foot_plane_u", 0.10)))
		var head_s: Dictionary = island.lounger_back_point(0.62)
		var mid_s: Dictionary = island.lounger_back_point(0.38)
		var back_n: Vector3 = (mid_s["normal"] as Vector3).normalized()
		var head_n: Vector3 = (head_s["normal"] as Vector3).normalized()
		var seat_n: Vector3 = (hip_s["normal"] as Vector3).normalized()
		# Mesh-near-bone gaps: contact ≤2 cm means the skin kisses the pad, not a bone capsule.
		# Bone + skin shell. Tight mesh probes only (r≤0.08) — wide probes read butt as spine.
		out["hips"] = _signed_gap(boy.lie_bone_world("mixamorig_Hips"), hip_s["pos"], seat_n) - 0.08
		out["spine"] = minf(
			_signed_gap(boy.lie_bone_world("mixamorig_Spine1"), mid_s["pos"], back_n) - 0.045,
			_signed_gap(boy.lie_bone_world("mixamorig_Spine2"), mid_s["pos"], back_n) - 0.045)
		out["head"] = _signed_gap(boy.lie_bone_world("mixamorig_Head"), head_s["pos"], head_n) - 0.055
		out["foot_l"] = _signed_gap(pts["foot_l"], foot_s["pos"], seat_n)
		out["foot_r"] = _signed_gap(pts["foot_r"], foot_s["pos"], seat_n)
	return out


## Closest skinned sample near a bone, signed along the support normal (sky-side positive).
func _mesh_gap_near(bone_pos: Vector3, surface: Vector3, normal: Vector3, radius: float) -> float:
	var samples: Array[Vector3] = boy.skinned_sample_world(500)
	normal = normal.normalized()
	var best := 1e9
	var hit := false
	for s in samples:
		if s.distance_to(bone_pos) > radius:
			continue
		hit = true
		best = minf(best, _signed_gap(s, surface, normal))
	if not hit:
		# Fallback: bone with a small shell.
		return _signed_gap(bone_pos - normal * 0.08, surface, normal)
	return best


## After a lounger hips-pitch, plant heels on the seat plane so they don't punch through.
func _plant_lie_feet() -> void:
	if rest_kind != "sun":
		return
	var foot_plane: Dictionary = island.lounger_seat_point(float(get_meta("lie_foot_plane_u", 0.05)))
	boy.lie_foot_plane_point = foot_plane["pos"]
	boy.lie_foot_plane_normal = foot_plane["normal"]
	boy.lie_foot_plant = true
	# Heels + knees above foam top; hips carry the thighs (no UpLeg override).
	boy.lie_foot_plant_gap = 0.015
	boy.plant_feet_on_plane(boy.lie_foot_plane_point, boy.lie_foot_plane_normal, boy.lie_foot_plant_gap, true)


## Deepest penetration of lie contact points into the support (negative = into the surface).
## Used by selftest: fail if any sample is deeper than 1 cm.
func lie_penetration_depth() -> float:
	var gaps: Dictionary = lie_contact_gaps()
	if gaps.is_empty():
		return 0.0
	var deepest := 0.0
	for k in gaps.keys():
		deepest = minf(deepest, float(gaps[k]))
	return deepest


## Skinned samples vs the rigid backrest BOARD under the foam. Foam kiss is OK.
func lie_backrest_penetration_depth() -> float:
	if rest_kind != "sun":
		return 1.0
	var samples: Array[Vector3] = boy.skinned_sample_world(280)
	if samples.is_empty():
		return 1.0
	var back: Dictionary = island.lounger_back_point(0.55)
	var back_n: Vector3 = (back["normal"] as Vector3).normalized()
	var foam_h: float = maxf(island.lounger_back_half.y * 2.0, 0.08)
	var board_pos: Vector3 = (back["pos"] as Vector3) - back_n * foam_h
	var foot_l: Vector3 = boy.lie_bone_world("mixamorig_LeftFoot")
	var foot_r: Vector3 = boy.lie_bone_world("mixamorig_RightFoot")
	var thigh_l: Vector3 = boy.lie_bone_world("mixamorig_LeftUpLeg")
	var thigh_r: Vector3 = boy.lie_bone_world("mixamorig_RightUpLeg")
	var hips_p: Vector3 = boy.lie_bone_world("mixamorig_Hips")
	var torso: Array[Vector3] = [
		boy.lie_bone_world("mixamorig_Spine1"),
		boy.lie_bone_world("mixamorig_Spine2"),
		boy.lie_bone_world("mixamorig_Head"),
	]
	var deepest := 1e9
	var hit := false
	for s in samples:
		if not island.lounger_back_contains(s, 0.04):
			continue
		if s.distance_to(foot_l) < 0.25 or s.distance_to(foot_r) < 0.25:
			continue
		if s.distance_to(thigh_l) < 0.18 or s.distance_to(thigh_r) < 0.18:
			continue
		if s.distance_to(hips_p) < 0.20:
			continue
		var near_torso := false
		for tp in torso:
			if s.distance_to(tp) < 0.28:
				near_torso = true
				break
		if not near_torso:
			continue
		var g := _signed_gap(s, board_pos, back_n)
		if g < -0.25:
			continue
		hit = true
		deepest = minf(deepest, g)
	return deepest if hit else 0.02


func lounger_back_slab_clear() -> float:
	return island.lounger_back_half.y * 2.0 + 0.08


## Skinned samples vs the rigid seat BOARD under the foam cushion.
## 2–4 cm foam compress is expected; failing means punching through the wood.
func lie_seat_penetration_depth() -> float:
	if rest_kind != "sun":
		return 1.0
	var samples: Array[Vector3] = boy.skinned_sample_world(360)
	if samples.is_empty():
		return 1.0
	var seat: Dictionary = island.lounger_seat_point(0.5)
	var seat_n: Vector3 = (seat["normal"] as Vector3).normalized()
	var foam_h: float = maxf(island.lounger_seat_half.y * 2.0, 0.06)
	var board_pos: Vector3 = (seat["pos"] as Vector3) - seat_n * foam_h
	var deepest := 1e9
	var hit := false
	for s in samples:
		if not island.lounger_seat_contains(s, 0.05):
			continue
		if island.lounger_back_contains(s, 0.02):
			continue
		var g := _signed_gap(s, board_pos, seat_n)
		# Ignore wrap-around under the thin board.
		if g < -0.25:
			continue
		hit = true
		deepest = minf(deepest, g)
	return deepest if hit else 0.02


## Skinned body (+ baked hat crown/brim verts) vs the support surface.
## Returns the deepest signed gap (negative = into the furniture). Selftest fails below −1 cm.
func lie_mesh_penetration_depth(include_hat := true) -> float:
	if rest_kind != "sun" and rest_kind != "sleep":
		return 0.0
	var samples: Array[Vector3] = boy.skinned_sample_world(450)
	# Include hat samples when the brim is still on the head (chest mode clears fabric).
	if include_hat and boy.hat_mode == "head":
		samples.append_array(boy.hat_sample_world(140))
	if samples.is_empty():
		return 0.0
	var deepest := 1e9
	var hit := false
	var swing := _lie_swing()
	if rest_kind == "sleep":
		var along: Vector3 = (island.hammock_b - island.hammock_a).normalized()
		var mid: Vector3 = (island.hammock_a + island.hammock_b) * 0.5
		var ham_len := maxf(island.hammock_a.distance_to(island.hammock_b), 0.01)
		# Torso contact chain — ignore far limb tips that clip the gathered ends.
		var torso: Array[Vector3] = [
			boy.lie_bone_world("mixamorig_Hips"),
			boy.lie_bone_world("mixamorig_Spine1"),
			boy.lie_bone_world("mixamorig_Spine2"),
			boy.lie_bone_world("mixamorig_Head"),
		]
		for s in samples:
			var near_torso := false
			for tp in torso:
				if s.distance_to(tp) < 0.28:
					near_torso = true
					break
			if not near_torso:
				continue
			var t := clampf(0.5 + (s - mid).dot(along) / ham_len, 0.06, 0.94)
			var fr: Dictionary = island.hammock_frame(t)
			var fp: Vector3 = swing * (fr["pos"] as Vector3)
			var fn: Vector3 = (swing.basis * (fr["normal"] as Vector3)).normalized()
			var side: Vector3 = (swing.basis * (fr["side"] as Vector3)).normalized()
			if absf((s - fp).dot(side)) > 0.48:
				continue
			hit = true
			deepest = minf(deepest, _signed_gap(s, fp, fn))
	else:
		var seat: Dictionary = island.lounger_seat_point(0.5)
		var back: Dictionary = island.lounger_back_point(0.45)
		var seat_n: Vector3 = (seat["normal"] as Vector3).normalized()
		var back_n: Vector3 = (back["normal"] as Vector3).normalized()
		var seat_pos: Vector3 = seat["pos"] as Vector3
		var back_pos: Vector3 = back["pos"] as Vector3
		# Planted heels sit on the seat — don't let foot-skin verts keep the lift loop alive.
		var foot_l: Vector3 = boy.lie_bone_world("mixamorig_LeftFoot")
		var foot_r: Vector3 = boy.lie_bone_world("mixamorig_RightFoot")
		var knee_l: Vector3 = boy.lie_bone_world("mixamorig_LeftLeg")
		var knee_r: Vector3 = boy.lie_bone_world("mixamorig_RightLeg")
		var thigh_l: Vector3 = boy.lie_bone_world("mixamorig_LeftUpLeg")
		var thigh_r: Vector3 = boy.lie_bone_world("mixamorig_RightUpLeg")
		# Upper-back / head skin only — hinge/hip/leg clips are seat-side geometry.
		var torso: Array[Vector3] = [
			boy.lie_bone_world("mixamorig_Spine2"),
			boy.lie_bone_world("mixamorig_Neck"),
			boy.lie_bone_world("mixamorig_Head"),
		]
		var hips_p: Vector3 = boy.lie_bone_world("mixamorig_Hips")
		for s in samples:
			# Legs are owned by seat plant / thigh pose — don't let them drive pad penet.
			if s.distance_to(foot_l) < 0.25 or s.distance_to(foot_r) < 0.25:
				continue
			if s.distance_to(knee_l) < 0.18 or s.distance_to(knee_r) < 0.18:
				continue
			if s.distance_to(thigh_l) < 0.18 or s.distance_to(thigh_r) < 0.18:
				continue
			if s.distance_to(hips_p) < 0.22:
				continue
			if island.lounger_back_contains(s, 0.04):
				var near_torso := false
				for tp in torso:
					if s.distance_to(tp) < 0.16:
						near_torso = true
						break
				if not near_torso:
					continue
				# Foam sink OK — fail only if we punch the wood board under the pad.
				var foam_b := maxf(island.lounger_back_half.y * 2.0, 0.08)
				var board_b := back_pos - back_n * foam_b
				var gb := _signed_gap(s, board_b, back_n)
				if gb < -0.25:
					continue
				hit = true
				deepest = minf(deepest, gb)
			elif island.lounger_seat_contains(s, 0.04):
				var foam_h := maxf(island.lounger_seat_half.y * 2.0, 0.06)
				var board := seat_pos - seat_n * foam_h
				var gs := _signed_gap(s, board, seat_n)
				if gs < -0.25:
					continue
				hit = true
				deepest = minf(deepest, gs)
	if not hit:
		return 0.0
	return deepest

func _wake() -> void:
	if mode == Mode.REST and rest_phase == 4:
		if rest_use_clips:
			rest_phase = 6
			rest_t = 0.0
			rest_clip_phase = "exit"
			_play_rest_exit_clip()
		else:
			rest_phase = 6 if rest_kind == "seat" and not seat_lying else 5
			rest_t = 0.0
		_update_ui()


func _clip_name(phase: String) -> String:
	match rest_clip_prop:
		"bench":
			return "bench_sit_%s" % phase
		"log":
			return "log_sit_%s" % phase
		"hammock":
			if phase == "idle":
				return "hammock_sleep"
			return "hammock_%s" % phase
	return ""


func _apply_boy_prop_root(clip_key: String) -> void:
	var cinfo: Dictionary = rest_align.get("clips", {}).get(clip_key, {})
	var rp: Array = cinfo.get("root_pos_prop", [0, 0, -0.5])
	var yaw_deg := float(cinfo.get("root_yaw_deg", 0.0))
	var local := Vector3(float(rp[0]), float(rp[1]), float(rp[2]))
	# Prop-frame placement exactly as authored (do NOT re-snap Y to terrain — slope was
	# burying the boy ~10–15 cm into the seat). player == boy, so never overwrite after.
	var pos := rest_prop_xf * local
	# alignment.json yaw 0 => faces +Z; boy.gd model.rotation.y = PI flips Mixamo +Z to game −Z,
	# so add PI when placing the boy node to match authored facing.
	var yaw := rest_prop_xf.basis.get_euler().y + deg_to_rad(yaw_deg) + PI
	boy.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	face_yaw = yaw
	ground_y = pos.y


func _play_rest_enter_clip() -> void:
	var clip := _clip_name("enter")
	rest_clip_phase = "enter"
	_apply_boy_prop_root(clip)
	boy.play_prop_clip(clip, false, 0.15)
	if rest_clip_prop == "hammock":
		island.set_hammock_clip_frame("hammock_enter", 0)
		boy.set_face_expr("idle")


func _play_rest_idle_clip() -> void:
	var clip := _clip_name("idle")
	rest_clip_phase = "idle"
	_apply_boy_prop_root(_clip_name("enter"))  # same root as enter
	boy.play_prop_clip(clip, true, 0.12)
	if rest_clip_prop == "hammock":
		island.set_hammock_clip_frame("hammock_sleep", 0)
		boy.set_face_expr("sleep")
	else:
		boy.set_face_expr("smile")


func _play_rest_exit_clip() -> void:
	var clip := _clip_name("exit")
	rest_clip_phase = "exit"
	_apply_boy_prop_root(_clip_name("enter"))
	boy.play_prop_clip(clip, false, 0.12)
	if rest_clip_prop == "hammock":
		island.set_hammock_clip_frame("hammock_exit", 0)
		boy.set_face_expr("idle")


func _finish_rest_exit() -> void:
	var clip := _clip_name("exit")
	var cinfo: Dictionary = rest_align.get("clips", {}).get(clip, {})
	var after: Dictionary = cinfo.get("after_exit", {})
	if after.has("new_root_pos_prop"):
		var np: Array = after["new_root_pos_prop"]
		var local := Vector3(float(np[0]), float(np[1]), float(np[2]))
		var pos := rest_prop_xf * local
		var yaw := rest_prop_xf.basis.get_euler().y + deg_to_rad(float(after.get("new_yaw_deg", 180.0))) + PI
		boy.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
		face_yaw = yaw
		ground_y = pos.y
		rest_approach = Vector3(pos.x, _surface(pos.x, pos.z), pos.z)
	else:
		# Fallback: end_root_shift in prop XZ (shift is [x,z]).
		var sh: Array = cinfo.get("end_root_shift_prop", [0, 0])
		var yaw_d := deg_to_rad(float(cinfo.get("end_yaw_delta_deg", 180.0)))
		var enter_key := _clip_name("enter")
		var einfo: Dictionary = rest_align.get("clips", {}).get(enter_key, {})
		var rp0: Array = einfo.get("root_pos_prop", [0, 0, -0.5])
		var local0 := Vector3(float(rp0[0]), float(rp0[1]), float(rp0[2]))
		var base := rest_prop_xf * local0
		var shift := rest_prop_xf.basis * Vector3(float(sh[0]), 0.0, float(sh[1]))
		var pos2 := base + shift
		# After exit: stand on terrain at the new XZ (authored pad should be flat).
		pos2.y = _surface(pos2.x, pos2.z)
		var yaw0 := rest_prop_xf.basis.get_euler().y + deg_to_rad(float(einfo.get("root_yaw_deg", 0.0))) + PI
		var yaw2 := yaw0 + yaw_d
		boy.global_transform = Transform3D(Basis(Vector3.UP, yaw2), pos2)
		face_yaw = yaw2
		ground_y = pos2.y
	boy.end_prop_clip(0.2)
	if rest_clip_prop == "hammock":
		island.set_hammock_clip_frame("empty", 0)
	island.set_hammock_load([] as Array[Vector3])
	move_vel = Vector3.ZERO
	ground_y = _surface(player.position.x, player.position.z)
	mode = Mode.EXPLORE
	# Ease back to follow from the last sit framing (don't snap behind).
	ex_yaw = cam_yaw
	ex_pitch = cam_pitch
	ex_dist = cam_dist
	rest_exit_cam_t = 0.8
	rest_use_clips = false
	rest_clip_phase = ""
	_update_action_kind()
	_update_ui()


func _sync_hammock_cloth_to_boy() -> void:
	if rest_clip_prop != "hammock":
		return
	var clip := boy.prop_clip
	if clip == "":
		return
	island.set_hammock_clip_frame(clip, boy.prop_clip_frame(24.0))


func _rest_tick_clips(delta: float) -> void:
	rest_t += delta
	match rest_phase:
		0:
			# Walk to the prop marker (approach).
			var d := rest_approach - player.position
			d.y = 0.0
			if d.length() < 0.08 or rest_t > 8.0:
				player.position = Vector3(rest_approach.x, player.position.y, rest_approach.z)
				move_vel = Vector3.ZERO
				boy.set_move(0.0)
				boy.set_idle()
				rest_phase = 1
				rest_t = 0.0
				_play_rest_enter_clip()
			else:
				var spd := minf(1.0, d.length() * 3.0 + 0.3)
				move_vel = move_vel.move_toward(d.normalized() * spd, 8.0 * delta)
				face_yaw = lerp_angle(face_yaw, atan2(-d.x, -d.z), 1.0 - exp(-delta * 10.0))
				var to := _try_move(player.position, move_vel * delta)
				if to.distance_to(player.position) < move_vel.length() * delta * 0.2 and rest_t > 0.5:
					# Stuck — snap ahead.
					player.position = Vector3(rest_approach.x, player.position.y, rest_approach.z)
				else:
					player.position = to
				player.position.y = _surface(player.position.x, player.position.z)
				player.rotation.y = face_yaw
				boy.global_position = player.global_position
				boy.rotation.y = face_yaw
				boy.set_move(move_vel.length())
		1, 2, 3:
			# Enter clip playing (root fixed; hips carry root-motion).
			_sync_hammock_cloth_to_boy()
			if boy.prop_clip_finished() or rest_t > boy.prop_clip_length() + 0.3:
				rest_phase = 4
				rest_t = 0.0
				_play_rest_idle_clip()
			zzz.visible = false
		4:
			# Idle / sleep loop.
			_sync_hammock_cloth_to_boy()
			zzz.visible = rest_kind == "sleep"
			if zzz.visible:
				var head: Vector3 = (boy.parts["head"] as Node3D).global_position
				var cyc := fmod(rest_t * 0.5, 1.0)
				zzz.text = ["z", "z Z", "z Z z", "z Z z"][int(cyc * 4.0) % 4]
				zzz.global_position = head + Vector3(0, 0.38 + cyc * 0.12, 0) + rest_side * 0.1
				zzz.modulate.a = 1.0 - smoothstep(0.75, 1.0, cyc)
		5, 6:
			# Exit clip.
			zzz.visible = false
			_sync_hammock_cloth_to_boy()
			if boy.prop_clip_finished() or rest_t > boy.prop_clip_length() + 0.35:
				_finish_rest_exit()
		_:
			pass
	_update_ui()


func _rest_tick(delta: float) -> void:
	if rest_frozen:
		# Shot / selftest hold: keep hammock sag + Zzz, do not advance phases.
		if rest_kind == "sleep" and rest_phase in [2, 3, 4, 5, 6]:
			if rest_use_clips:
				_sync_hammock_cloth_to_boy()
			else:
				_update_hammock_load()
			if rest_phase == 4:
				zzz.visible = true
				var head_z: Vector3 = (boy.parts["head"] as Node3D).global_position
				zzz.global_position = head_z + Vector3(0, 0.42, 0) + rest_side * 0.1
				zzz.modulate.a = 0.85
			else:
				zzz.visible = false
		return
	if rest_use_clips:
		_rest_tick_clips(delta)
		return
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
			var root: Vector3
			if sleep:
				# Side perch → settle onto mid fabric; lift clears the rail.
				var edge := rest_approach.lerp(rest_root_sit, 0.55)
				edge.y = maxf(edge.y, rest_root_sit.y + 0.06)
				root = rest_approach.lerp(edge, clampf(ks * 1.35, 0.0, 1.0)).lerp(rest_root_sit, smoothstep(0.45, 1.0, ks))
				root.y += 0.14 * sin(PI * ks)
			else:
				root = rest_approach.lerp(rest_root_sit, ks)
				# Clear the seat board mid-lerp; settle by snap near the end.
				var is_log_exit := rest_kind == "seat" and seat_i >= 0 and seat_i < island.seats.size() \
					and String(island.seats[seat_i].get("name", "")) == "坐木"
				root.y += (0.20 if is_log_exit else 0.14) * sin(PI * ks)
				if rest_phase == 6:
					# Hold seat-height Y until the sit clip has mostly stood up.
					var stand_u := smoothstep(0.08, 0.55, 1.0 - ks)
					var y_pad := 0.14 if is_log_exit else 0.05
					var y_hold := lerpf(rest_root_sit.y + y_pad, rest_approach.y, stand_u)
					root.y = maxf(root.y, y_hold)
					# Slide further off the seat so standing legs don't clip the log volume.
					var away: Vector3 = rest_approach - rest_seat
					away.y = 0.0
					if away.length() > 0.05:
						root += away.normalized() * ((0.28 if is_log_exit else 0.12) * (1.0 - ks))
			swing = island.swing_hammock(swing_amp * sin(gt * 1.3)) if sleep else Transform3D.IDENTITY
			boy.global_transform = swing * Transform3D(rest_sit_b, root)
			# Seat exit: live mesh clearance against the seat top footprint.
			if rest_kind == "seat" and rest_phase == 6 and seat_i >= 0 and seat_i < island.seats.size():
				var st_ex: Dictionary = island.seats[seat_i]
				var top_ex: Vector3 = st_ex["top"]
				var face_ex: Vector3 = seat_face.normalized()
				var side_ex: Vector3 = rest_side.normalized() if rest_side.length() > 0.1 else face_ex.cross(Vector3.UP).normalized()
				var hips_ex: Vector3 = boy.lie_bone_world("mixamorig_Hips")
				var dig_ex := 1e9
				var hit_ex := false
				for s_ex in boy.skinned_sample_world(500):
					if s_ex.distance_to(hips_ex) > 0.38:
						continue
					if s_ex.y > hips_ex.y + 0.05:
						continue
					var lat_ex: float = (s_ex - top_ex).dot(side_ex)
					var along_ex: float = (s_ex - top_ex).dot(-face_ex)
					if absf(lat_ex) > 0.70 or along_ex < -0.22 or along_ex > 0.45:
						continue
					hit_ex = true
					dig_ex = minf(dig_ex, s_ex.y - top_ex.y)
				if hit_ex and dig_ex < -0.008:
					root.y += minf(-dig_ex + 0.02, 0.16)
					var away2: Vector3 = rest_approach - rest_seat
					away2.y = 0.0
					if away2.length() > 0.05:
						root += away2.normalized() * minf(-dig_ex, 0.10)
					boy.global_transform = Transform3D(rest_sit_b, root)
			if rest_kind == "seat" and rest_phase == 2 and ks > 0.72:
				_snap_sit_contact()
				pl = boy.activity("seat", 1.0, 0.0, gt)
				rest_root_sit = rest_seat - rest_sit_b * pl
				var settled := rest_approach.lerp(rest_root_sit, ks)
				settled.y += 0.08 * sin(PI * ks)
				boy.global_transform = Transform3D(rest_sit_b, settled)
			if sleep and rest_phase == 2 and ks > 0.70:
				_snap_sit_contact()
				pl = boy.activity("sleep", 1.0, 0.0, gt)
				rest_root_sit = rest_seat - rest_sit_b * pl
				boy.global_transform = Transform3D(rest_sit_b, rest_root_sit)
				_update_hammock_load()
			if rest_t >= dur:
				rest_t = 0.0
				if rest_phase == 2:
					if rest_kind == "seat":
						_snap_sit_contact()
						pl = boy.activity("seat", 1.0, 0.0, gt)
						rest_root_sit = rest_seat - rest_sit_b * pl
					elif sleep:
						_snap_sit_contact()
						pl = boy.activity("sleep", 1.0, 0.0, gt)
						rest_root_sit = rest_seat - rest_sit_b * pl
						_update_hammock_load()
					rest_phase = 4 if rest_kind == "seat" else 3
					_update_ui()
				else:
					boy.end_activity()
					if sleep:
						island.set_hammock_load([] as Array[Vector3])
					player.position = _blocked_by(rest_approach)
					player.rotation = Vector3(0, face_yaw, 0)
					ground_y = _surface(player.position.x, player.position.z)
					move_vel = Vector3.ZERO
					mode = Mode.EXPLORE
					ex_yaw = cam_yaw
					ex_pitch = cam_pitch
					ex_dist = cam_dist
					rest_exit_cam_t = 0.8
					_update_action_kind()
					_update_ui()
		3, 5:
			var dur2 := SEAT_LIE_DUR if rest_kind == "seat" else LIE_BLEND_DUR
			var k2 := clampf(rest_t / dur2, 0.0, 1.0)
			if rest_phase == 5:
				k2 = 1.0 - k2
			var ks2 := smoothstep(0.0, 1.0, k2)
			var pl2 := boy.activity(_act_kind(), 1.0, k2, gt)
			var b := rest_sit_b.slerp(rest_lie_b, ks2)
			var w := rest_seat.lerp(rest_lie, ks2) + Vector3(0, 0.10 * sin(PI * k2), 0)
			if rest_kind == "sun":
				# Keep butt/back/hat clear of lounger foam during tip-back AND tip-up (exit).
				# Prior lifts still dug ~11 cm into the pad mid-exit — clear the foam fully.
				w.y += 0.24 * sin(PI * k2)
				var back_n: Vector3 = (-rest_lie_b.z).normalized()
				if back_n.y < 0.15:
					back_n = Vector3.UP
				w += back_n * (0.14 * sin(PI * k2))
			if rest_kind == "seat" and island.seats[seat_i]["name"] == "长椅":
				# shuffles forward on the seat as he turns to lie back: head (and hat) clear of the backrest
				w += seat_face * 0.18 * sin(PI * k2)
			if sleep:
				# Stay above the fabric while tipping into/out of the cradle; snap settles at phase 4.
				var ham_n: Vector3 = (island.hammock_frame(0.5)["normal"] as Vector3).normalized()
				w += ham_n * (0.20 * sin(PI * k2))
				swing_amp = lerpf(swing_amp, 0.06 * ks2 + 0.01, 1.0 - exp(-delta * 2.0))
				swing = island.swing_hammock(swing_amp * sin(gt * 1.3))
				_update_hammock_load()
			boy.global_transform = swing * Transform3D(b, w - b * pl2)
			# Lounger tip (enter+exit): if mid-blend still penetrates, lift fully clear.
			if rest_kind == "sun" and rest_phase in [3, 5] and rest_t > 0.15:
				var dig: float = lie_mesh_penetration_depth(true)
				if dig < -0.008:
					w += Vector3.UP * minf(-dig + 0.01, 0.14)
					boy.global_transform = Transform3D(b, w - b * pl2)
			if rest_t >= dur2:
				if sleep and rest_phase == 5:
					island.set_hammock_load([] as Array[Vector3])
				rest_t = 0.0
				rest_phase = 4 if rest_phase == 3 else 6
				if rest_phase == 6 and rest_kind == "seat":
					seat_lying = false
				_update_ui()
		4 when rest_kind == "seat" and not seat_lying:
			# lie_k must stay 0 — lie_k=1 switches the pelvis local offset and digs the butt into the board.
			boy.activity("seat", 1.0, 0.0, rest_t)
			boy.global_transform = Transform3D(rest_sit_b, rest_root_sit)
			# Keep butt on the seat if the sit clip drifts.
			if fmod(rest_t, 0.35) < delta:
				_snap_sit_contact()
				var pl_s := boy.activity("seat", 1.0, 0.0, gt)
				rest_root_sit = rest_seat - rest_sit_b * pl_s
				boy.global_transform = Transform3D(rest_sit_b, rest_root_sit)
		4:
			# Drop prior foot overrides before posing — planted knees while hips float
			# stretch Tripo thighs through the cushion.
			if rest_kind == "sun":
				boy.clear_foot_plant()
			var pl3 := boy.activity(_act_kind(), 1.0, 1.0, gt)
			if sleep:
				swing_amp = lerpf(swing_amp, 0.07, 1.0 - exp(-delta * 1.0))
				swing = island.swing_hammock(swing_amp * sin(gt * 1.3))
			boy.global_transform = swing * Transform3D(rest_lie_b, rest_lie - rest_lie_b * pl3)
			# contact snap so skinned mesh sits on the support (few passes — over-iterating walks off the pad)
			if rest_t > 0.05 and (not get_meta("lie_snapped", false) or fmod(rest_t, 1.5) < delta):
				var passes := 6 if not get_meta("lie_snapped", false) else 2
				for _pass in passes:
					_snap_lie_contact()
					pl3 = boy.activity(_act_kind(), 1.0, 1.0, gt)
					boy.global_transform = swing * Transform3D(rest_lie_b, rest_lie - rest_lie_b * pl3)
				set_meta("lie_snapped", true)
			if sleep:
				_update_hammock_load()
			_plant_lie_feet()
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
	# Empty hammock: light resting sag.
	if island.hammock_occupied:
		island.set_hammock_load([] as Array[Vector3])


## Push hip / shoulder / heel samples into the deformable hammock so the fabric takes his weight.
func _update_hammock_load() -> void:
	var pts: Array[Vector3] = []
	pts.append(boy.lie_bone_world("mixamorig_Hips"))
	pts.append(boy.lie_bone_world("mixamorig_Spine1"))
	pts.append(boy.lie_bone_world("mixamorig_Spine2"))
	pts.append(boy.lie_bone_world("mixamorig_Head"))
	pts.append(boy.lie_bone_world("mixamorig_LeftFoot"))
	pts.append(boy.lie_bone_world("mixamorig_RightFoot"))
	island.set_hammock_load(pts)


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
			_rest_cam_input(event)

## every tap also retries the Web Audio unlock (iOS may suspend the context after a call / app switch)
func _poke_audio(event: InputEvent) -> void:
	if not is_web or not audio_started:
		return
	if (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and not event.pressed):
		JavaScriptBridge.eval("window.__unlockAudio && window.__unlockAudio()", true)

func _explore_cam_input(event: InputEvent) -> void:
	# one finger (outside the joystick) drags the camera; pinch / wheel zooms
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
		else:
			touches.erase(event.index)
		dragging = touches.size() > 0
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
				zoom_pending *= pinch_d / d
			pinch_d = d
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			mouse_drag = event.pressed
			dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_nudge_zoom(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_nudge_zoom(1.11)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and mouse_drag:
		_explore_orbit(event.relative)
	elif event is InputEventMagnifyGesture:
		_nudge_zoom(1.0 / maxf(event.factor, 0.05))

func _explore_orbit(rel: Vector2) -> void:
	var vs := get_viewport().get_visible_rect().size
	var k: float = 5.0 / max(min(vs.x, vs.y), 200.0)
	# Accumulate; applied once in _update_camera so multi-event ProMotion frames don't stutter.
	orbit_pending += Vector2(-rel.x * k, rel.y * k * 0.6)
	orbit_vel = Vector2(-rel.x * k * 12.0, rel.y * k * 8.0)
	if mode == Mode.REST:
		rest_touch_dragged = true
	last_drag = gt


var _orbit_ease := 0.0

func _flush_orbit_pending() -> void:
	if orbit_pending.length_squared() < 1e-12 and absf(zoom_pending - 1.0) < 1e-6:
		_orbit_ease = move_toward(_orbit_ease, 0.0, 0.25)
		return
	# Ease drag-start so the first frames don't dump a full delta onto a lagging cam.
	_orbit_ease = move_toward(_orbit_ease, 1.0, 0.28)
	var ease_k := smoothstep(0.0, 1.0, _orbit_ease)
	var dy := orbit_pending.x * ease_k
	var dp := orbit_pending.y * ease_k
	orbit_pending = Vector2.ZERO
	# Keep live cam angles in lockstep with the orbit targets (no lag→spike).
	if cam_fixed:
		fix_yaw += dy
		fix_pitch = clampf(fix_pitch + dp, 0.06, 1.35)
		cam_yaw = fix_yaw
		cam_pitch = fix_pitch
	elif mode == Mode.REST:
		rest_cam_yaw += dy
		rest_cam_pitch = clampf(rest_cam_pitch + dp, 0.06, 1.15)
		cam_yaw = rest_cam_yaw
		cam_pitch = rest_cam_pitch
	elif mode == Mode.VIEW:
		view_yaw += dy
		view_pitch = clamp(view_pitch + dp, 0.06, 1.42)
		cam_yaw = view_yaw
		cam_pitch = view_pitch
	else:
		ex_yaw += dy
		ex_pitch = clamp(ex_pitch + dp, 0.05, 1.25)
		cam_yaw = ex_yaw
		cam_pitch = ex_pitch
	if absf(zoom_pending - 1.0) > 1e-6:
		var z := zoom_pending
		zoom_pending = 1.0
		if cam_fixed:
			fix_dist = clampf(fix_dist * z, 2.5, 28.0)
			cam_dist = fix_dist
		elif mode == Mode.REST:
			rest_cam_dist = clampf(rest_cam_dist * z, 1.6, 7.5)
			cam_dist *= z
		elif mode == Mode.VIEW:
			view_dist = clamp(view_dist * z, 4.0, 95.0)
			cam_dist = view_dist
		else:
			ex_dist = clamp(ex_dist * z, 3.0, 14.0)
			cam_dist = ex_dist


## Orbit / zoom while sitting or sleeping; a tap with no drag still stands up.
func _rest_cam_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 1:
				rest_touch_dragged = false
		else:
			var was_drag := rest_touch_dragged
			touches.erase(event.index)
			dragging = touches.size() > 0
			if touches.is_empty() and not was_drag:
				_wake()
			return
		dragging = touches.size() > 0
		if touches.size() == 2:
			var ps: Array = touches.values()
			pinch_d = (ps[0] - ps[1]).length()
	elif event is InputEventScreenDrag:
		var prev: Vector2 = touches.get(event.index, event.position)
		touches[event.index] = event.position
		if touches.size() == 1:
			if (event.position - prev).length() > 2.0:
				rest_touch_dragged = true
			_explore_orbit(event.position - prev)
		elif touches.size() >= 2:
			rest_touch_dragged = true
			var ps2: Array = touches.values()
			var d: float = (ps2[0] - ps2[1]).length()
			if pinch_d > 1.0 and d > 1.0:
				rest_cam_dist = clampf(rest_cam_dist * pinch_d / d, 1.6, 7.5)
			pinch_d = d
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			mouse_drag = event.pressed
			dragging = event.pressed
			if event.pressed:
				rest_touch_dragged = false
			elif not rest_touch_dragged:
				_wake()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			rest_cam_dist = clampf(rest_cam_dist * 0.9, 1.6, 7.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			rest_cam_dist = clampf(rest_cam_dist * 1.11, 1.6, 7.5)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and mouse_drag:
		if event.relative.length() > 1.0:
			rest_touch_dragged = true
		_explore_orbit(event.relative)
	elif event is InputEventMagnifyGesture:
		rest_cam_dist = clampf(rest_cam_dist / maxf(event.factor, 0.05), 1.6, 7.5)

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

## Throwing on a phone: put a finger down (on the stone pad, or anywhere that is not a button) and swipe out
## towards the sea - the swipe's direction on screen is the aim, its length the power; letting go throws, and
## the speed of the finger as it lets go is the spin (a flick spins the stone, a slow release barely does).
## Swiping back towards the kid cancels. Desktop: the same with the mouse, or keys (see _throw_keys).
func _throw_input(event: InputEvent) -> void:
	var now := Time.get_ticks_usec() / 1e6
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if state == State.READY and not throw_walk:
				_swipe_press(event.position, now)
		elif state == State.AIMING and aim_src == "swipe":
			_swipe_release(event.position, now)
	elif event is InputEventMouseMotion and state == State.AIMING and aim_src == "swipe":
		_swipe_move(event.position, now)
	elif event is InputEventKey and event.physical_keycode == KEY_SPACE and not event.echo:
		if event.pressed and state == State.READY and not throw_walk:
			_begin_aim(Vector2.ZERO, "key")
		elif not event.pressed and state == State.AIMING and aim_src == "key":
			throw_spin = KEY_SPIN
			_throw()

## arrow keys / A D aim, W S (or up / down) the launch elevation, Q E the stone's tilt; hold space to charge
func _throw_keys(delta: float) -> void:
	if mode != Mode.THROW or throw_walk or not (state == State.READY or (state == State.AIMING and aim_src == "key")):
		return
	var k := func(a: Key, b: Key) -> float: return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0
	var turn: float = k.call(KEY_LEFT, KEY_A) - k.call(KEY_RIGHT, KEY_D)
	var el: float = k.call(KEY_UP, KEY_W) - k.call(KEY_DOWN, KEY_S)
	var tl: float = k.call(KEY_E, KEY_PAGEUP) - k.call(KEY_Q, KEY_PAGEDOWN)
	if turn != 0.0:
		aim_yaw = clampf(aim_yaw + turn * 0.8 * delta, -AIM_LIM, AIM_LIM)
	if el != 0.0 or tl != 0.0:
		key_angles += Vector2(el * 14.0, tl * 16.0) * delta
		_set_angles(aim_pitch + key_angles.x, aim_tilt + key_angles.y)
		# whole degrees, but holding the key keeps creeping
		key_angles -= Vector2(roundf(key_angles.x), roundf(key_angles.y))
	else:
		key_angles = Vector2.ZERO

func _set_angles(el: float, tilt: float) -> void:
	aim_pitch = clampf(roundf(el), EL_MIN, EL_MAX)
	aim_tilt = clampf(roundf(tilt), 0.0, TILT_MAX)
	el_slider.set_value(aim_pitch)
	tilt_slider.set_value(aim_tilt)

## scripted / keyboard charge: the power bar ping-pongs while held (POWER_CYCLE)
func _begin_aim(p: Vector2, src := "script") -> void:
	state = State.AIMING
	aim_src = src
	press_pos = p
	charge_t = 0.0
	power = 0.0
	yaw_at_press = aim_yaw
	_update_ui()

func _swipe_unit() -> float:
	var vs := get_viewport().get_visible_rect().size
	return minf(vs.x, vs.y)

func _swipe_press(p: Vector2, t: float) -> void:
	state = State.AIMING
	aim_src = "swipe"
	press_pos = p
	swipe_hist = [[t, p]]
	swipe_d = Vector2.ZERO
	charge_t = 0.0
	power = 0.0
	yaw_at_press = aim_yaw
	view_at_press = cam_aim_yaw
	_update_ui()

func _swipe_move(p: Vector2, t: float) -> void:
	swipe_hist.append([t, p])
	swipe_move_frame = Engine.get_process_frames()
	while swipe_hist.size() > 3 and t - float(swipe_hist[1][0]) > 0.5:
		swipe_hist.pop_front()
	_apply_swipe(p - press_pos)

func _swipe_release(p: Vector2, t: float) -> void:
	# a slow device can hand over the lift a frame after the finger's last move: it left the glass moving
	var last: Array = swipe_hist[swipe_hist.size() - 1]
	if swipe_hist.size() > 1 and Engine.get_process_frames() - swipe_move_frame <= 1 and p.distance_to(last[1]) < _swipe_unit() * 0.02:
		t = minf(t, float(last[0]))
	swipe_hist.append([t, p])
	var fl := _flick(swipe_hist)
	_apply_swipe(fl[1] if fl[1] != null else p - press_pos)
	throw_spin = fl[0]
	_throw()

## power from the swipe's length, aim from its direction; pointing back towards the kid means "cancel"
func _apply_swipe(d: Vector2) -> void:
	swipe_d = d
	var unit := _swipe_unit()
	if d.y > unit * 0.03 or d.length() < unit * SWIPE_DEAD:
		power = 0.0
		aim_yaw = yaw_at_press
		return
	power = clampf((d.length() - unit * SWIPE_DEAD) / (unit * SWIPE_FULL), 0.0, 1.0)
	# at most 70 deg off straight up: a sideways swipe is not a throw along the dock
	var a := atan2(d.x, -d.y)
	if absf(a) > deg_to_rad(70.0):
		var c := signf(a) * deg_to_rad(70.0)
		d = Vector2(sin(c), -cos(c)) * d.length()
	aim_yaw = _swipe_yaw(d)

## The swipe's angle off straight up is the aim's angle off the view line the camera had when the finger
## went down (it sits right behind the release point). A true screen-to-water projection would squeeze a
## 30 deg swipe into ~7 deg near the horizon, which feels dead under the thumb.
func _swipe_yaw(d: Vector2) -> float:
	return clampf(wrapf(view_at_press - atan2(d.x, -d.y), -PI, PI), -AIM_LIM, AIM_LIM)

## Spin from how fast the finger was going when it let go (over the last ~90 ms). A finger that rested on
## an aim and then flicked (within ~0.2 s) throws the aim it rested on, so aiming carefully and then
## flicking works as well as one quick swipe. Returns [spin 0.2..1, the rested swipe vector or null].
func _flick(hist: Array) -> Array:
	var unit := _swipe_unit()
	var n := hist.size()
	var t1: float = hist[n - 1][0]
	var p1: Vector2 = hist[n - 1][1]
	var j := n - 1
	while j > 0 and t1 - float(hist[j - 1][0]) <= 0.09:
		j -= 1
	# a slow frame can hand over a whole flick at once (moves merged, all stamped with the same time): measure
	# from the sample before it, as if that was at most 50 ms ago
	var dt := t1 - float(hist[j][0])
	if dt < 1.0 / 240.0 and j > 0:
		j -= 1
		dt = minf(t1 - float(hist[j][0]), 0.05)
	var speed := 0.0
	if j < n - 1:
		speed = (p1 - (hist[j][1] as Vector2)).length() / maxf(dt, 1.0 / 120.0) / unit
	var s := clampf(0.2 + 0.8 * smoothstep(0.6, 3.2, speed), 0.2, 1.0)
	var held: Variant = null
	if speed > 1.5:
		for k in range(n - 1, 0, -1):
			var a: Array = hist[k - 1]
			var b: Array = hist[k]
			var v := ((b[1] as Vector2) - (a[1] as Vector2)).length() / maxf(float(b[0]) - float(a[0]), 1e-3) / unit
			if v < 0.5:
				var hd: Vector2 = (a[1] as Vector2) - press_pos
				if t1 - float(a[0]) < 0.22 and hd.length() > unit * 0.12 and hd.y < 0.0:
					held = hd
				break
	return [s, held]

# ------------------------------------------------------------------ physics
# After Clanet, Hersen & Bocquet, "Secrets of successful stone-skipping" (Nature 2004): the stone's own tilt
# to the water (attack angle) works best near 20 deg; its flight path must come in low (the steepest entry
# that still bounces shrinks for a badly tilted, slow or spin-less stone); every bounce costs a roughly fixed
# amount of kinetic energy (so the number of skips grows with the speed squared), more for a badly tilted
# stone; spin keeps the tilt steady - without it the stone wobbles and pitches up a little at each bounce.

static func launch_speed(p: float) -> float:
	return lerp(7.0, 25.0, p)

## scripted throws (demos): spin from power
static func launch_spin(p: float) -> float:
	return clamp(0.35 + 0.65 * p, 0.0, 1.0)

## 0..1: how well the stone meets the water at this tilt (a spin-less stone wobbles off it)
static func tilt_quality(tilt: float, s: float) -> float:
	return exp(-pow((absf(tilt - TILT_BEST) + 9.0 * (1.0 - s)) / 14.0, 2.0))

## steepest entry angle (deg) that still bounces
static func max_entry(tilt: float, s: float, vh: float) -> float:
	return 30.0 * (0.25 + 0.75 * tilt_quality(tilt, s)) * clampf(vh / 12.0, 0.65, 1.0) * (0.85 + 0.15 * s)

## slowest horizontal speed (m/s) that still bounces
static func min_speed(tilt: float, s: float) -> float:
	return 3.5 / (0.35 + 0.65 * tilt_quality(tilt, s))

## One touch of the water: [bounced, velocity after, spin after, tilt after, entry angle, why it sank]
## (why: "" | "slow" | "steep" entry | "flat" stone slapped | "tilt" stone dug in). jitter -1..1 (0 in the sim).
static func water_contact(v: Vector3, s: float, tilt: float, jitter: float) -> Array:
	var h := Vector2(v.x, v.z)
	var vh := h.length()
	var ang := rad_to_deg(atan2(-v.y, maxf(vh, 0.001)))
	if tilt > 50.0:
		return [false, v, s, tilt, ang, "tilt"]
	if vh < min_speed(tilt, s):
		return [false, v, s, tilt, ang, "slow"]
	if ang > max_entry(tilt, s, vh) + jitter * 2.0:
		# would a well-tilted stone have made it? then the tilt is what sank it
		if ang <= max_entry(TILT_BEST, s, vh) + jitter * 2.0:
			return [false, v, s, tilt, ang, "flat" if tilt < TILT_BEST else "tilt"]
		return [false, v, s, tilt, ang, "steep"]
	var q := tilt_quality(tilt, s)
	var loss := 9.0 * (1.0 + 3.0 * (1.0 - q)) * (1.0 + 1.2 * (1.0 - s))
	var nvh := sqrt(maxf(vh * vh - loss, 0.0)) * (1.0 - 0.5 * sin(deg_to_rad(ang)))
	var e := (0.45 + 0.2 * s) * (0.8 + 0.4 * clampf((tilt - 5.0) / 30.0, 0.0, 1.0))
	var nh := h / vh * nvh
	return [true, Vector3(nh.x, maxf(-v.y * e, 0.55), nh.y), s * 0.975, tilt + (1.0 - s) * (1.2 + 4.0 * jitter), ang, ""]

## a whole throw over open water without jitter: {skips, dist, entry (first, deg), why}
static func simulate(p: Vector3, v: Vector3, s: float, tilt: float) -> Dictionary:
	var o := p
	var n := 0
	var entry := -1.0
	var why := ""
	for i in 40000:
		v.y -= GRAVITY * 0.002
		p += v * 0.002
		if p.y <= 0.02 and v.y < 0.0:
			p.y = 0.02
			var r := water_contact(v, s, tilt, 0.0)
			if entry < 0.0:
				entry = r[4]
			if not r[0]:
				why = r[5]
				break
			n += 1
			v = r[1]
			s = r[2]
			tilt = r[3]
	return {"skips": n, "dist": Vector2(p.x - o.x, p.z - o.z).length(), "entry": entry, "why": why}

func _aim_dir() -> Vector3:
	return Vector3(0, 0, -1).rotated(Vector3.UP, aim_yaw)

## where the stone leaves the kid's hand (the release key pose, power independent)
func _hand_pos() -> Vector3:
	return _ideal_hand(aim_yaw)

## the release point if he faced `yaw` (the throw turns him square to the aim before the release)
func _ideal_hand(yaw: float) -> Vector3:
	var b := Basis(Vector3.UP, yaw).scaled(player.global_basis.get_scale())
	return player.global_position + b * boy.release_local

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
		_hide_preview()
		_update_ui()
		return
	if aim_src == "script":
		throw_spin = launch_spin(power)
	# the swing starts now; the stone leaves the hand on the release frame (Boy.released -> _launch)
	state = State.THROWING
	boy.start_throw(power)
	_play("whoosh", lerpf(-13.0, -3.0, power), lerpf(0.85, 1.15, power) * rng.randf_range(0.96, 1.04))
	_hide_preview()
	_update_ui()

func _hide_preview() -> void:
	for d in preview_dots:
		d.visible = false
	preview_ring.visible = false

func _launch() -> void:
	if state != State.THROWING:
		return
	state = State.FLYING
	fly_t = 0.0
	stone_pos = _hand_pos()
	throw_origin = stone_pos
	stone_vel = _initial_velocity()
	spin = clampf(throw_spin * rng.randf_range(0.95, 1.03), 0.1, 1.0)
	stone_tilt = aim_tilt + rng.randf_range(-1.5, 1.5)
	launch_spin_v = spin
	first_entry = -1.0
	spin_ang = 0.0
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
	_orient_stone(dt)
	if _hdist(stone_pos) > 1.0:
		var hit := _hit_test(stone_pos)
		if hit != "":
			_hit_sound(hit)
			throw_dist = _hdist(stone_pos)
			result_text = hit + ("" if skips == 0 else "（之前漂了 %d 下）" % skips)
			last_tip = "朝开阔的海面瞄准"
			stone_vel = Vector3(0, -1.0, 0)
			state = State.SINKING
			sink_timer = 0.6
			if stone_pos.y < 0.3:
				_splash(Vector3(stone_pos.x, 0.0, stone_pos.z), 0.6, false, Vector3.ZERO)
				_play("sink", -8.0, rng.randf_range(1.0, 1.15))
			return
	if stone_pos.y <= 0.02 and stone_vel.y < 0.0:
		stone_pos.y = 0.02
		var res := water_contact(stone_vel, spin, stone_tilt, rng.randf_range(-1, 1))
		throw_dist = _hdist(stone_pos)
		if first_entry < 0.0:
			first_entry = res[4]
		if res[0]:
			skips += 1
			stone_vel = res[1]
			spin = res[2]
			stone_tilt = res[3]
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
			elif skips == 20:
				_toast("20 连跳！完美！")
				_play("combo", -3.0, 1.4)
			for bn in island.buoys:
				if Vector2(stone_pos.x - bn.position.x, stone_pos.z - bn.position.z).length() < 2.0:
					_toast("擦过浮标！")
		else:
			_splash(stone_pos, 1.2, true, Vector3.ZERO)
			_play("sink", -2.0 + rng.randf_range(-1.0, 1.0), rng.randf_range(0.92, 1.06))
			_judge(res[5], res[4])
			state = State.SINKING
			sink_timer = 0.0
	elif state == State.FLYING and skips > 0:
		throw_dist = max(throw_dist, _hdist(stone_pos))
	_update_ui()

## the stone flies nose-up by its tilt and spins flat about its own axis; with little spin it wobbles
func _orient_stone(dt: float) -> void:
	stone.position = stone_pos
	spin_ang += spin * 40.0 * dt
	var f := Vector3(stone_vel.x, 0, stone_vel.z)
	if f.length() < 0.1:
		f = _aim_dir()
	var wob := (1.0 - spin) * 0.35 * sin(fly_t * 9.0)
	var b := Basis(Vector3.UP, atan2(-f.x, -f.z)) * Basis(Vector3.RIGHT, deg_to_rad(stone_tilt)) \
		* Basis(Vector3.FORWARD, wob) * Basis(Vector3.UP, spin_ang)
	stone.basis = b * Basis.from_scale(Vector3(0.7, 0.24, 0.6))

## when the stone goes under: the toast says what happened, the hint bar keeps a quiet tip for the next go
func _judge(why: String, ang: float) -> void:
	var tip := ""
	var tilt := aim_tilt
	if skips == 0:
		match why:
			"tilt":
				result_text = "扑通！石头倾角太陡，一头扎进水里"
				tip = "倾角 20° 左右最好"
			"flat":
				result_text = "啪！石头太平，拍在水面上停住了"
				tip = "倾角调到 20° 左右：前端微微翘起"
			"slow":
				result_text = "扑通！速度不够，沉了"
				tip = "往海面划得更长 = 更用力"
			_:
				result_text = "扑通！入水角 %d°，太陡了" % roundi(ang)
				if tilt < 10.0 or tilt > 32.0:
					tip = "倾角 %d° 不合适，调到 20° 左右" % roundi(tilt)
				elif aim_pitch > 10.0:
					tip = "出手仰角 %d° 太高，放低一点" % roundi(aim_pitch)
				elif power < 0.6:
					tip = "划得更长、更用力，石头飞得更平"
				elif launch_spin_v < 0.45:
					tip = "松手时顺势快甩，转起来的石头更稳"
				else:
					tip = "试试半蹲，出手更低"
	else:
		result_text = "漂了 %d 下！" % skips
		if launch_spin_v < 0.45:
			tip = "旋转不足：松手时顺势快速一甩"
		elif tilt < 12.0:
			tip = "倾角偏平：跳得矮、停得快，20° 左右最好"
		elif tilt > 28.0:
			tip = "倾角偏陡：每跳都损失很多速度"
		elif first_entry > 22.0:
			tip = "入水偏陡（%d°），放低仰角会跳得更多" % roundi(first_entry)
		elif power < 0.7:
			tip = "多用点力，跳得更多"
		elif skips >= 15:
			tip = "完美的一甩！"
	last_tip = "上一投：入水 %d° · 倾角 %d° · 旋转 %d%%" % [roundi(maxf(first_entry, 0.0)), roundi(tilt), roundi(launch_spin_v * 100.0)]
	if tip != "":
		last_tip += "\n" + tip

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

## Nearest path lantern → soft radial ground pool in the terrain shader (round falloff,
## not the dirt-path strip lit by a hard Omni).
func _update_path_lamp_pool() -> void:
	var k := smoothstep(0.0, 1.0, night_k)
	if k < 0.02 or island == null or island.terrain_mat == null:
		if island and island.terrain_mat:
			island.terrain_mat.set_shader_parameter("lamp_pool", 0.0)
		return
	var focus := player.global_position if player else camera.global_position
	var best := Vector3(9999.0, 0.0, 9999.0)
	var best_d := 1e9
	for L in island.lamps:
		if str(L[1]) != "path":
			continue
		var lp: Vector3 = L[0]
		var d := Vector2(lp.x - focus.x, lp.z - focus.z).length()
		if d < best_d:
			best_d = d
			best = lp
	# Fade in only when a path lamp is nearby so beach/campfire scenes stay untouched.
	var near := 1.0 - smoothstep(6.0, 14.0, best_d)
	island.terrain_mat.set_shader_parameter("lamp_xz", Vector2(best.x, best.z))
	island.terrain_mat.set_shader_parameter("lamp_pool", k * near)

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

## Aim preview: the flight to the first touch of the water (bright dots), a ring where it lands coloured by
## how that touch will go (green bounces, amber marginal, coral sinks) and, faint, the next two hops.
func _update_preview() -> void:
	var p := _hand_pos()
	var v := _initial_velocity()
	var s := throw_spin if aim_src != "swipe" else 0.8
	var tilt := aim_tilt
	var dt := 0.05
	var placed := 0
	var hop := 0
	var verdict := 2
	var ring_at := Vector3.ZERO
	var ok := power >= 0.04
	var steps := 0
	while placed < preview_dots.size() and steps < 400 and ok:
		steps += 1
		v.y -= GRAVITY * dt
		p += v * dt
		if _hit_test(p) != "" and Vector2(p.x - player.position.x, p.z - player.position.z).length() > 1.0:
			if hop == 0:
				verdict = 0
				ring_at = p
			break
		if p.y <= 0.02 and v.y < 0.0:
			p.y = 0.02
			var r := water_contact(v, s, tilt, 0.0)
			if hop == 0:
				ring_at = p
				var vh := Vector2(v.x, v.z).length()
				if not r[0]:
					verdict = 0
				elif float(r[4]) > max_entry(tilt, s, vh) - 4.0 or vh < min_speed(tilt, s) * 1.25:
					verdict = 1
			if not r[0] or hop >= 2:
				break
			hop += 1
			v = r[1]
			s = r[2]
			tilt = r[3]
			continue
		# bright dots every step on the way out, sparser and faint on the hops
		if hop == 0 or steps % 2 == 0:
			var d := preview_dots[placed]
			d.visible = true
			d.global_position = p
			d.scale = Vector3.ONE * (1.0 if hop == 0 else 0.6)
			d.set_meta("hop", hop)
			placed += 1
	for i in range(placed, preview_dots.size()):
		preview_dots[i].visible = false
	var col: Color = [Color(1.0, 0.5, 0.42), Color(1.0, 0.82, 0.35), Color(0.55, 0.95, 0.65)][verdict]
	for i in placed:
		var d := preview_dots[i]
		(d.material_override as StandardMaterial3D).albedo_color = Color(col, 0.9 if int(d.get_meta("hop")) == 0 else 0.4)
	preview_ring.visible = ok and ring_at != Vector3.ZERO
	if preview_ring.visible:
		preview_ring.global_position = Vector3(ring_at.x, 0.03, ring_at.z)
		(preview_ring.material_override as StandardMaterial3D).albedo_color = Color(col, 0.85)

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

## day <-> sunset <-> night over ~2.8 s: sky, sun→moon, ambient, fog, water, lamps, fire, sounds
func _update_night(delta: float, force := false) -> void:
	var target := 1.0 if night_on else 0.0
	var settled := night_k == target and not force
	if not settled:
		night_k = move_toward(night_k, target, delta / 2.8)
	var k := smoothstep(0.0, 1.0, night_k)
	# Sunset lobe peaks mid-transition (warm low sun), then yields to moonlight.
	var sunset := smoothstep(0.05, 0.32, k) * (1.0 - smoothstep(0.48, 0.82, k))
	# Keep boy materials synced every frame at night (expression swaps can reset albedo).
	if settled:
		var moon_s := sun.global_basis.z.normalized() if sun else Vector3.ZERO
		if boy:
			boy.set_night_k(k, moon_s)
		return
	RenderingServer.global_shader_parameter_set("night_k", k)
	sky_mat.sky_top_color = Color(0.40, 0.58, 0.76).lerp(Color(0.05, 0.09, 0.20), k)
	sky_mat.sky_horizon_color = Color(0.78, 0.85, 0.88).lerp(Color(1.0, 0.55, 0.28), sunset).lerp(Color(0.12, 0.18, 0.32), k)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color(0.30, 0.46, 0.52).lerp(Color(0.04, 0.07, 0.14), k)
	var qd := Basis.from_euler(SUN_DAY * PI / 180.0).get_rotation_quaternion()
	var qs := Basis.from_euler(Vector3(-8, 55, 0) * PI / 180.0).get_rotation_quaternion()
	var qn := Basis.from_euler(MOON_NIGHT * PI / 180.0).get_rotation_quaternion()
	var q_mid := qd.slerp(qs, clampf(sunset * 2.0, 0.0, 1.0))
	sun.basis = Basis(q_mid.slerp(qn, clampf((k - 0.35) / 0.55, 0.0, 1.0)))
	# Moon: soft cool key + ambient fill so boy and sand share the same exposure.
	var moon_e := lerpf(1.0, 0.32, k)
	sun.light_energy = lerpf(moon_e, 1.15, sunset * 0.55)
	sun.light_color = Color(1.0, 0.93, 0.82).lerp(Color(1.0, 0.48, 0.22), sunset).lerp(Color(0.91, 0.93, 1.0), k)
	sun.shadow_blur = lerpf(2.5, 5.0, k)
	sun.light_angular_distance = lerpf(1.2, 3.5, k)
	# Soft moon shadows — canopy mustn't crush the path to pure black.
	sun.shadow_opacity = lerpf(1.0, 0.22, k)
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY if k > 0.55 else DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	env.ambient_light_color = Color(0.22, 0.30, 0.50).lerp(Color(0.45, 0.28, 0.18), sunset).lerp(Color(0.38, 0.40, 0.48), k)
	env.ambient_light_sky_contribution = lerpf(1.0, 0.28, k)
	# Stronger constant ambient fill so path/grass/roots still read under foliage.
	env.ambient_light_energy = lerpf(0.55, 0.78, k)
	env.fog_light_color = Color(0.80, 0.86, 0.88).lerp(Color(0.95, 0.55, 0.30), sunset).lerp(Color(0.18, 0.20, 0.28), k)
	env.fog_density = lerpf(0.0045, 0.0024, k)
	# Filmic at night — ACES was crushing dim terrain to 0/255 under the canopy.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = lerpf(0.95, 1.12, k)
	env.tonemap_white = lerpf(3.2, 4.2, k)
	env.adjustment_saturation = lerpf(1.05, 0.98, k)
	env.adjustment_contrast = lerpf(1.02, 0.97, k)
	env.adjustment_brightness = lerpf(0.98, 1.04, k)
	var moon := sun.global_basis.z.normalized()
	island.water_mat.set_shader_parameter("glint_dir", moon)
	island.water_mat.set_shader_parameter("glint_col", Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.55, 0.28), sunset).lerp(Color(0.90, 0.93, 1.0), k))
	island.water_mat.set_shader_parameter("glint_gain", lerpf(1.0, 2.15, k))
	island.water_mat.set_shader_parameter("night", k)
	# Lantern glass / hut window panes: visible warm sources at night.
	# Keep boost modest — path flame tip is tiny; high boost reads as a billboard.
	island.glow_mat.set_shader_parameter("boost", lerpf(0.35, 1.05, k))
	island.cloud_mat.set_shader_parameter("tint", Color(1, 1, 1).lerp(Color(0.10, 0.12, 0.20), k))
	island.campfire.night = k
	for tn in island.torches:
		tn.night = k
	for b in birds:
		(b["node"] as Node3D).visible = k < 0.45
	if night_amb:
		night_amb.volume_db = lerpf(-60.0, -13.0, sqrt(k))
	if boy:
		boy.set_night_k(k, moon)

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

## web ?hatprobe=1: every drawn frame, the hat against the seat boy.gd keeps it in on his head bone, per game
## state -> window.__hat (read by the mobile browser check)
var hat_probe := {"frames": 0, "max_mm": 0.0, "max_deg": 0.0, "worst": "", "off_head_frames": 0, "states": {}}

func _hat_probe_tick() -> void:
	var e := boy.hat_offset_error()
	var st: String = str(Mode.keys()[mode]).to_lower() + "/" + (rest_kind if mode == Mode.REST else boy.anim)
	hat_probe["frames"] += 1
	if boy.hat_s > 0.0 and mode != Mode.REST:
		hat_probe["off_head_frames"] += 1
	var s: Dictionary = hat_probe["states"]
	var r: Array = s.get(st, [0, 0.0, 0.0])
	s[st] = [int(r[0]) + 1, maxf(float(r[1]), e.x * 1000.0), maxf(float(r[2]), boy.hat_s)]
	if e.x * 1000.0 > float(hat_probe["max_mm"]):
		hat_probe["max_mm"] = e.x * 1000.0
		hat_probe["worst"] = st
	hat_probe["max_deg"] = maxf(float(hat_probe["max_deg"]), rad_to_deg(e.y))
	hat_probe["state"] = st
	hat_probe["hat_s"] = boy.hat_s
	hat_probe["act"] = action_btn.text if action_btn.visible else ""
	hat_probe["rest_phase"] = rest_phase
	JavaScriptBridge.eval("window.__hat = " + JSON.stringify(hat_probe), true)

## &at=dock|hammock|towel|bench: start next to it, so the browser check can rest there with the real buttons
func _hat_probe_place(at: String) -> void:
	var td := island.towel_dir
	var sd := td.cross(Vector3.UP).normalized()
	var spots := []
	var want: String = {"hammock": "sleep", "towel": "sun", "bench": "seat", "dock": "throw"}.get(at, "")
	match at:
		"dock":
			spots = [Vector3(0.2, 0, island.dock_end_z + 1.5)]
		"hammock":
			var hs := _hammock_spot()
			spots = [hs[0] + hs[2] * 1.6, hs[0] - hs[2] * 1.6]
		"towel":
			# the beach chair on the +side wins the button within 1.25 m of its approach: start on the far side
			spots = [island.towel_pos - sd * 1.0, island.towel_pos - sd * 1.3]
		"bench":
			var st: Dictionary = island.seats[0]
			spots = [_blocked_by((st["approach"] as Vector3) + (st["face"] as Vector3) * 0.4), st["approach"]]
	for p: Vector3 in spots:
		_place(p, 0.0)
		_update_action_kind()
		if action_kind == want:
			break
	_snap_explore_cam()

## When > 0, timing/selftest scripts force this as the sim delta so soft-GL
## (slow frames) still advances at the requested fps instead of walking 10× farther.
var sim_dt_override := 0.0

func _process(delta: float) -> void:
	if sim_dt_override > 0.0:
		delta = sim_dt_override
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
	_update_path_lamp_pool()
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
			if aim_src != "swipe":
				charge_t += delta
				power = pingpong(charge_t / (POWER_CYCLE * 0.5), 1.0)
			power_bar.value = power
			boy.charge(power)
			_update_preview()
			lbl_aim.text = _aim_readout()
		State.READY:
			if mode == Mode.THROW and not throw_walk:
				boy.set_idle()
		State.FLYING, State.SINKING:
			fly_t += delta
	_throw_keys(delta)
	if mode == Mode.THROW and throw_walk:
		_throw_walk_tick(delta)
	elif mode == Mode.THROW and (state == State.READY or state == State.AIMING or state == State.THROWING):
		_turn_to_aim(delta)
	else:
		boy.aim_twist = lerpf(boy.aim_twist, 0.0, 1.0 - exp(-delta * 8.0))
	_update_throw_pad()
	_update_camera(delta)
	var focus := player.global_position + Vector3(0, 0.7, 0)
	if demo_nocut:
		focus.y = -100.0
	island.foliage_mat.set_shader_parameter("focus", focus)
	island.leaf_mat.set_shader_parameter("focus", focus)
	island.static_mat.set_shader_parameter("focus", focus)
	island.torch_mat.set_shader_parameter("focus", focus)
	# Keep the see-through cone tight. Explore used to punch a solid grey sky-hole through
	# the canopy on iPhone (cut_radius 5.2); spring-arm pull-in handles occlusion instead.
	var cr_foliage := 2.2 if mode == Mode.EXPLORE else 1.6
	var cr_static := 1.7 if mode == Mode.EXPLORE else 1.4
	island.foliage_mat.set_shader_parameter("cut_radius", cr_foliage)
	island.leaf_mat.set_shader_parameter("cut_radius", cr_foliage)
	island.static_mat.set_shader_parameter("cut_radius", cr_static)
	island.torch_mat.set_shader_parameter("cut_radius", cr_static)
	if island.leaf_mat:
		island.leaf_mat.set_shader_parameter("near_fade", mq.leaf_near_fade if mq else 1.1)
	_update_prints()
	_update_audio(delta)
	_audio_tick(delta)
	if mq:
		mq.watch_frame(delta, get_viewport(), sun, refl_level, _set_refl_level)

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

## Throw-mode camera: right behind the stone in his hand, looking along the aim over his shoulder, so the
## aim line runs up the screen. While a finger is down it turns part way towards the aim, and all the way
## once the stone is thrown.
func _throw_cam() -> Array:
	var tall := _tall()
	var dir := Vector3(0, 0, -1).rotated(Vector3.UP, cam_aim_yaw)
	var h := _ideal_hand(cam_aim_yaw)
	# look at a point on the aim line `ahead` m out, from `back` m behind the hand and `high` m up
	var ahead := 7.0 if tall else 9.0
	var back := 4.0 if tall else 4.6
	var high := 2.6 if tall else 2.5
	var t := Vector3(h.x, 0.6, h.z) + dir * ahead
	return [t, cam_aim_yaw, atan2(high - 0.6, ahead + back), Vector2(ahead + back, high - 0.6).length()]

## the chest turns to the aim first and the hips and feet follow; once the swing starts they square up fast
func _turn_to_aim(delta: float) -> void:
	var r := player.rotation.y
	if state == State.READY:
		player.rotation.y = lerp_angle(r, aim_yaw, 1.0 - exp(-delta * 10.0))
		boy.aim_twist = lerpf(boy.aim_twist, 0.0, 1.0 - exp(-delta * 10.0))
		return
	r = lerp_angle(r, aim_yaw, 1.0 - exp(-delta * (26.0 if state == State.THROWING else 2.5)))
	var tw := wrapf(aim_yaw - r, -PI, PI)
	if absf(tw) > TWIST_MAX:
		r = aim_yaw - signf(tw) * TWIST_MAX
		tw = signf(tw) * TWIST_MAX
	player.rotation.y = r
	boy.aim_twist = tw

func _aim_readout() -> String:
	var deg := wrapf(rad_to_deg(aim_yaw), -180.0, 180.0)
	var dir := "正前方" if absf(deg) < 0.5 else ("左 %d°" % roundi(deg) if deg > 0.0 else "右 %d°" % roundi(-deg))
	var p := _hand_pos()
	var v := _initial_velocity()
	var vy := sqrt(maxf(v.y * v.y + 2.0 * GRAVITY * maxf(p.y - 0.02, 0.0), 0.0))
	var entry := rad_to_deg(atan2(vy, Vector2(v.x, v.z).length()))
	return "力度 %d%% · %s · 入水约 %d°（仰角 %d° · 倾角 %d°）" % [roundi(power * 100.0), dir, roundi(entry), roundi(aim_pitch), roundi(aim_tilt)]

func _update_throw_pad() -> void:
	var on := mode == Mode.THROW and not throw_walk
	var ang_on := on and (state == State.READY or state == State.AIMING)
	el_slider.visible = ang_on
	tilt_slider.visible = ang_on
	throw_pad.visible = on
	var aiming := on and state == State.AIMING and aim_src == "swipe"
	var show := on and state == State.READY
	var cancel := aiming and power <= 0.0 and swipe_d.length() > _swipe_unit() * SWIPE_DEAD
	var tip := ""
	if aiming:
		tip = "往回拉 = 取消" if cancel else ("%d%%" % roundi(power * 100.0) if power > 0.0 else "")
	if show != throw_pad.show_pad or aiming != throw_pad.aiming or (aiming and (throw_pad.to != press_pos + swipe_d or throw_pad.power != power)) \
			or tip != throw_pad.tip_text:
		throw_pad.show_pad = show
		throw_pad.aiming = aiming
		throw_pad.from = press_pos
		throw_pad.to = press_pos + swipe_d
		throw_pad.power = power
		throw_pad.cancel = cancel
		throw_pad.tip_text = tip
		throw_pad.queue_redraw()
	if mode == Mode.THROW:
		# while swiping it swings only part way, so the flight line stays on a narrow portrait screen
		var to := aim_yaw
		if state == State.AIMING and aim_src == "swipe":
			to = view_at_press + wrapf(aim_yaw - view_at_press, -PI, PI) * 0.6
		cam_aim_yaw = lerp_angle(cam_aim_yaw, to, 1.0 - exp(-get_process_delta_time() * 5.0))

func _explore_cam() -> Array:
	var tall := _tall()
	# Tripo: aim a little higher so the baked face stays readable under the brim
	var hy := 0.68 if boy.meta.get("tripo", false) else 0.55
	var t := player.global_position + Vector3(0, hy, 0)
	return [t, ex_yaw, ex_pitch, ex_dist * (1.1 if tall else 1.0)]

func _rest_bone(name: String, fallback: Vector3) -> Vector3:
	if boy and boy.skel:
		var p: Vector3 = boy.lie_bone_world(name)
		if p.length_squared() > 1e-6:
			return p
	return fallback


## Live sit/sleep look-at: chest/face centred so the boy sits in the middle third.
func _rest_cam_target() -> Vector3:
	var hips := _rest_bone("mixamorig_Hips", boy.global_position + Vector3(0, 0.55, 0))
	var head := _rest_bone("mixamorig_Head", boy.global_position + Vector3(0, 1.15, 0))
	if rest_phase <= 1 and rest_root_sit.length_squared() > 1e-6:
		var walk_t := player.global_position.lerp(rest_root_sit, clampf(rest_t * 0.55, 0.0, 1.0))
		return walk_t + Vector3(0, 0.72, 0)
	if rest_kind == "sleep" or seat_lying:
		# Bias toward the face so the cradle + expression read.
		return hips.lerp(head, 0.62)
	if rest_kind == "seat":
		return hips.lerp(head, 0.48)
	return hips.lerp(head, 0.42)


func _rest_face_fwd() -> Vector3:
	if rest_kind == "seat" and seat_face.length_squared() > 1e-6:
		var f := seat_face
		f.y = 0.0
		if f.length_squared() > 1e-6:
			return f.normalized()
	return Vector3(-sin(face_yaw), 0.0, -cos(face_yaw))


## Ideal distance so boy+prop fill ~45–60% of portrait height (KEEP_HEIGHT FOV).
func _rest_frame_dist(fig_h: float) -> float:
	var tall := _tall()
	var fov_v := deg_to_rad(66.0 if tall else 52.0)
	var fill := 0.52
	var d := (fig_h / fill) / (2.0 * tan(fov_v * 0.5))
	return clampf(d, 2.15, 4.0)


func _rest_cam() -> Array:
	var head := _rest_bone("mixamorig_Head", boy.global_position + Vector3(0, 1.15, 0))
	var hips := _rest_bone("mixamorig_Hips", boy.global_position + Vector3(0, 0.55, 0))
	var t := _rest_cam_target()
	var fig_h := maxf(head.y - (hips.y - 0.55), 1.05)
	if rest_kind == "sleep" or seat_lying:
		fig_h = 1.20
	var dist := _rest_frame_dist(fig_h)
	var pitch := 0.16
	if rest_kind == "sleep" or seat_lying:
		pitch = 0.24
	elif rest_kind == "seat":
		pitch = 0.14
	if rest_cam_yaw == INF:
		var pick: Array = _pick_rest_framing(t, head, hips, pitch, dist)
		var adj0: Array = _rest_los_adjust(t, head, float(pick[0]), float(pick[1]), float(pick[2]))
		rest_cam_yaw = float(adj0[0])
		rest_cam_pitch = float(adj0[1])
		rest_cam_dist = float(adj0[2])
	elif rest_cam_ease < 0.95 and not dragging:
		# While easing onto the framing, keep clearing LOS; stop fighting once the user orbits.
		var adj: Array = _rest_los_adjust(t, head, rest_cam_yaw, rest_cam_pitch, rest_cam_dist)
		rest_cam_yaw = float(adj[0])
		rest_cam_pitch = float(adj[1])
		rest_cam_dist = float(adj[2])
	return [t, rest_cam_yaw, rest_cam_pitch, rest_cam_dist]


## Front three-quarter (±25–35° off facing). Hammock: side-of-face, slightly above.
## Picks the ± side with clearer sea/scenery behind the boy and a clear LOS to the head.
func _pick_rest_framing(t: Vector3, head: Vector3, hips: Vector3, pitch: float, dist: float) -> Array:
	var cands: Array = []
	if rest_kind == "sleep" or seat_lying:
		var side := rest_side
		side.y = 0.0
		if side.length_squared() < 1e-6:
			side = Vector3.RIGHT
		else:
			side = side.normalized()
		var along := head - hips
		along.y = 0.0
		if along.length_squared() < 1e-6:
			along = (island.hammock_b - island.hammock_a)
			along.y = 0.0
		along = along.normalized() if along.length_squared() > 1e-6 else Vector3.FORWARD
		# Side of the face, a touch toward the feet so eyes/mouth read (not crown-only).
		for sgn in [-1.0, 1.0]:
			var dir: Vector3 = (side * sgn * 0.92 - along * 0.28).normalized()
			var yaw := atan2(dir.x, dir.z)
			cands.append([yaw, pitch, dist])
			cands.append([yaw, pitch + 0.06, dist * 0.95])
	else:
		var face := _rest_face_fwd()
		for ang_deg in [28.0, 32.0, 25.0, 35.0]:
			var ang := deg_to_rad(ang_deg)
			for sgn in [-1.0, 1.0]:
				# Camera in front of the boy, angled off his facing.
				var dir: Vector3 = face.rotated(Vector3.UP, sgn * ang)
				var yaw := atan2(dir.x, dir.z)
				cands.append([yaw, pitch, dist])
	var best: Array = cands[0]
	var best_score := -INF
	for c in cands:
		var yaw: float = float(c[0])
		var p: float = float(c[1])
		var d: float = float(c[2])
		var cam := t + Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * d
		var score := _score_rest_view(t, head, cam, yaw, p, d)
		if score > best_score:
			best_score = score
			best = [yaw, p, d]
	return best


func _score_rest_view(t: Vector3, head: Vector3, cam: Vector3, yaw: float, pitch: float, dist: float) -> float:
	var score := 0.0
	if _rest_los_blocked(cam, head):
		score -= 40.0
	elif _rest_los_blocked(cam, t):
		score -= 18.0
	# Prefer open water / low ground behind the boy (continuation past look-at).
	var toward := (t - cam)
	toward.y = 0.0
	if toward.length_squared() > 1e-6:
		toward = toward.normalized()
		var beyond := t + toward * 10.0
		var gh := Island.ground_h(beyond.x, beyond.z)
		if gh < 0.12:
			score += 8.0
		score += clampf(0.6 - gh * 0.25, -2.0, 3.0)
	# Torch poles near the look line are expensive (log sit).
	for ob in island.obstacles:
		if String(ob[3]).find("火把") < 0 and String(ob[3]).find("torch") < 0:
			continue
		var c2: Vector2 = ob[0]
		var closest := Geometry3D.get_closest_point_to_segment(Vector3(c2.x, cam.y, c2.y), cam, head)
		if Vector2(closest.x - c2.x, closest.z - c2.y).length() < float(ob[1]) + 0.35:
			score -= 12.0
	# Prefer camera not buried in terrain.
	var floor_y := maxf(Island.ground_h(cam.x, cam.z), 0.0) + 0.35
	if cam.y < floor_y:
		score -= 20.0
	score -= absf(dist - 2.8) * 0.15
	score -= absf(pitch - 0.18) * 0.5
	return score


## Ray from camera to head: trunks, torch/obstacle cylinders, terrain mounds.
func _rest_los_blocked(cam: Vector3, head: Vector3) -> bool:
	for tr: Array in island.trunks:
		if _seg_hits_trunk(cam, head, tr):
			return true
	for ob in island.obstacles:
		var c2: Vector2 = ob[0]
		var top_y: float = float(ob[2])
		var bot_y: float = float(ob[4]) if ob.size() > 4 else 0.0
		var rad: float = float(ob[1]) + 0.12
		var closest := Geometry3D.get_closest_point_to_segment(Vector3(c2.x, 0.5 * (bot_y + top_y), c2.y), cam, head)
		if closest.y < bot_y - 0.1 or closest.y > top_y + 0.15:
			continue
		if Vector2(closest.x - c2.x, closest.z - c2.y).length() < rad:
			return true
	# Terrain bite: sample along the ray; ground poking above the ray blocks.
	var n := 6
	for i in range(1, n):
		var u := float(i) / float(n)
		var p: Vector3 = cam.lerp(head, u)
		var gh := Island.ground_h(p.x, p.z)
		if p.y < gh + 0.28:
			return true
	return false


## If LOS is blocked, pull in / nudge yaw·pitch until the head is clear.
func _rest_los_adjust(t: Vector3, head: Vector3, yaw: float, pitch: float, dist: float) -> Array:
	var y := yaw
	var p := pitch
	var d := dist
	for n in 10:
		var cam := t + Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * d
		var floor_y := maxf(Island.ground_h(cam.x, cam.z), 0.0) + 0.35
		if cam.y < floor_y:
			p = clampf(p + 0.05, 0.08, 0.55)
			cam.y = floor_y
		if not _rest_los_blocked(cam, head):
			return [y, p, d]
		d = maxf(d * 0.88, 1.55)
		y += 0.11 * (1.0 if n % 2 == 0 else -1.0)
		p = clampf(p + 0.035, 0.08, 0.55)
	return [y, p, d]


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

func _snap_explore_cam(front := false) -> void:
	# follow-behind while exploring; optional 3/4-front for start / face checks
	ex_yaw = face_yaw + PI + 0.45 if front else face_yaw
	var c := _explore_cam()
	cam_target = c[0]; cam_yaw = c[1]; cam_pitch = c[2]; cam_dist = c[3]

func _toggle_cam_fixed() -> void:
	cam_fixed = not cam_fixed
	if cam_fixed:
		# Freeze at the current follow framing (retarget if already resting).
		var c: Array
		if mode == Mode.REST:
			c = _rest_cam()
		elif mode == Mode.VIEW:
			c = [cam_target, view_yaw, view_pitch, view_dist]
		else:
			c = _explore_cam()
		fix_target = c[0]
		fix_yaw = float(c[1])
		fix_pitch = float(c[2])
		fix_dist = float(c[3])
		cam_target = fix_target
		cam_yaw = fix_yaw
		cam_pitch = fix_pitch
		cam_dist = fix_dist
	_persist_cam_fixed()
	_update_ui()


func _nudge_zoom(factor: float) -> void:
	zoom_pending *= factor


func _persist_cam_fixed() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("try{localStorage.setItem('ss_cam_fixed',%s)}catch(e){}" % ("'1'" if cam_fixed else "'0'"), true)


func _load_cam_fixed() -> void:
	if not OS.has_feature("web"):
		return
	var v = JavaScriptBridge.eval("try{localStorage.getItem('ss_cam_fixed')}catch(e){null}", true)
	cam_fixed = str(v) == "1"


func _update_camera(delta: float) -> void:
	_flush_orbit_pending()
	if demo_cam:
		if demo_track.size() > 0:
			var tr: Array = demo_track
			cam_target = player.global_position + Vector3(0, tr[3], 0)
			cam_yaw = (float(tr[0]) if tr.size() > 4 else face_yaw + float(tr[0]))
			cam_pitch = tr[1]
			cam_dist = tr[2]
		_apply_camera(delta)
		return
	# Fixed mode: never auto-follow while exploring; on REST soft-retarget once so
	# sit/lie aren't off-frame after toggling 固定视角 in explore.
	if cam_fixed and mode != Mode.THROW:
		if mode == Mode.REST and not get_meta("fix_rest_locked", false):
			var rc: Array = _rest_cam()
			fix_target = rc[0]
			fix_yaw = float(rc[1])
			fix_pitch = float(rc[2])
			fix_dist = float(rc[3])
			set_meta("fix_rest_locked", true)
		if not dragging:
			orbit_vel *= exp(-delta * 3.5)
			fix_yaw += orbit_vel.x * delta
			fix_pitch = clampf(fix_pitch + orbit_vel.y * delta, 0.06, 1.25)
			cam_dist = lerpf(cam_dist, fix_dist, 1.0 - exp(-delta * 5.0))
		else:
			cam_dist = fix_dist
		cam_target = fix_target
		cam_yaw = fix_yaw
		cam_pitch = fix_pitch
		if dragging:
			cam_dist = fix_dist
		_apply_camera(delta)
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
	elif mode == Mode.REST and rest_phase >= 1:
		# Smooth ~0.8 s ease onto the per-prop face-forward framing; orbit edits rest_cam_*.
		want = _rest_cam()
		rest_cam_ease = minf(rest_cam_ease + delta / 0.8, 1.0)
		var ease_k := smoothstep(0.0, 1.0, rest_cam_ease)
		# While easing in, blend faster toward the framing; after, track tightly (orbit feels direct).
		k = lerpf(1.0 - exp(-delta * 2.2), 1.0 - exp(-delta * 10.0), ease_k)
		if dragging:
			k = 1.0 - exp(-delta * 14.0)
	else:
		# explore follow camera: drags turn it, otherwise it slowly swings in behind the walking kid
		if cur_speed > 0.3 and gt - last_drag > 1.5:
			var rate := 0.6 + 0.5 * clampf(cur_speed / RUN_SPEED, 0.0, 1.0)
			ex_yaw = lerp_angle(ex_yaw, face_yaw, 1.0 - exp(-delta * rate))
		want = _explore_cam()
		# Near-lock follow while moving so accel doesn't shove the boy across the screen.
		var move_k := clampf(cur_speed / maxf(WALK_MAX, 0.01), 0.0, 1.0)
		k = 1.0 - exp(-delta * lerpf(10.0, 28.0, move_k))
		if dragging or orbit_pending.length_squared() > 1e-10:
			# Drag: angles already snapped in _flush_orbit_pending; keep target tight.
			k = 1.0
		if mode == Mode.REST:
			k = 1.0 - exp(-delta * 3.0)
		# Soft return from sit/sleep framing to follow-behind.
		if rest_exit_cam_t > 0.0:
			rest_exit_cam_t = maxf(rest_exit_cam_t - delta, 0.0)
			k = 1.0 - exp(-delta * lerpf(1.6, 5.0, 1.0 - rest_exit_cam_t / 0.8))
	cam_target = cam_target.lerp(want[0], k)
	if dragging or orbit_pending.length_squared() > 1e-10 or _orbit_ease > 0.01:
		cam_yaw = want[1]
		cam_pitch = want[2]
		cam_dist = want[3]
	else:
		cam_yaw = lerp_angle(cam_yaw, want[1], k)
		cam_pitch = lerp(cam_pitch, want[2], k)
		cam_dist = lerp(cam_dist, want[3], k)
	_apply_camera(delta)

func _cam_blocked(q: Vector3) -> bool:
	# Always respect small prop blockers (crates / posts) so explore doesn't hide the boy.
	for bl in island.cam_blockers:
		if q.distance_to(bl[0]) < float(bl[1]):
			return true
	if mode == Mode.THROW or mode == Mode.VIEW:
		return false
	for ob in island.obstacles:
		var c: Vector2 = ob[0]
		if q.y < float(ob[2]) and q.y > float(ob[4]) and Vector2(q.x - c.x, q.z - c.y).length() < float(ob[1]) + 0.25:
			return true
	return false

var _cam_arm_k := 1.0
var _cam_arm_want := 1.0
## Smoothed lateral dodge (m along camera-right). Never snaps — was the walk_120 boy_ds spike.
var _cam_slide := 0.0
var _cam_slide_want := 0.0

func _apply_camera(delta: float = 1.0 / 60.0) -> void:
	var full_off := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch)) * cam_dist
	# Soft spring arm: frame-rate independent pull-in (no constant-α snap at 120Hz).
	var want_k := 1.0
	var orbiting := dragging or orbit_pending.length_squared() > 1e-10 or _orbit_ease > 0.05
	if cam_dist < 20.0 and (not demo_cam or demo_track.size() > 0):
		for i in range(2, 28):
			var q := cam_target + full_off * (i / 27.0)
			if _cam_blocked(q):
				want_k = maxf((i - 1) / 27.0, 1.35 / maxf(cam_dist, 0.01))
				break
	# During orbit, hold arm length — probe flicker was the cam_ds spike source.
	if orbiting:
		want_k = _cam_arm_k
	# Hysteresis: don't chatter when the probe flips a step.
	if absf(want_k - _cam_arm_want) > 0.035:
		_cam_arm_want = want_k
	# Pull-in limited/smoothed; recover (push out) even slower so clearance doesn't ping-pong.
	var arm_rate := 2.8 if orbiting else (3.4 if _cam_arm_want < _cam_arm_k - 0.01 else 2.0)
	_cam_arm_k = lerpf(_cam_arm_k, _cam_arm_want, 1.0 - exp(-delta * arm_rate))
	var off := full_off * _cam_arm_k
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	# Lateral dodge only while nearly idle. During walk/run a sideways hop shoves the boy
	# across the screen (walk_120 spike); prefer smoothed arm pull-in along the look axis
	# so look_at(cam_target) keeps him centred. Follow target is never rewritten here.
	_cam_slide_want = 0.0
	var moving := cur_speed > 0.12
	if mode == Mode.EXPLORE and not orbiting:
		var probe := cam_target + off
		if _cam_blocked(probe):
			if not moving:
				for s in [0.55, -0.55, 1.1, -1.1, 1.8, -1.8, 2.4, -2.4]:
					if not _cam_blocked(probe + right * s):
						_cam_slide_want = s
						break
			# Deeper arm pull (smoothed) — never teleport.
			if _cam_slide_want == 0.0:
				for kk in [0.82, 0.68, 0.54, 0.42, 0.32]:
					if not _cam_blocked(cam_target + full_off * kk):
						_cam_arm_want = minf(_cam_arm_want, kk)
						break
	# Idle dodge eases in/out slowly; while moving, bleed any leftover slide away.
	var slide_rate := (1.6 if absf(_cam_slide_want) > absf(_cam_slide) else 2.4) if not moving else 4.0
	if moving:
		_cam_slide_want = 0.0
	_cam_slide = lerpf(_cam_slide, _cam_slide_want, 1.0 - exp(-delta * slide_rate))
	var pos := cam_target + off + right * _cam_slide
	var floor_y: float = max(Island.ground_h(pos.x, pos.z), 0.0) + 0.55
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
	# Mobile / web: drop internal 3D res so UI stays crisp while GPU fill falls (~DPR 3 → ~1.5–2×).
	mq.setup(is_web, _opt("mobile") == "1", get_viewport(), sun)
	mq.changed.connect(func(_t: int) -> void: _apply_mq_materials())
	_apply_mq_materials()
	var want := _opt("refl", "auto")
	refl_auto = want == "auto"
	# On phones start one step lighter so the first walk doesn't hitch on full reflection.
	var start_l := 1 if mq.mobile else 0
	_set_refl_level({"0": 2, "low": 1}.get(want, start_l))
	if _opt("shadow") == "0":
		_set_refl_level(3)
	# lights whose glitter streaks across the waves at night: the campfire, the lighthouse, then the lamps
	var pos := PackedVector4Array()
	var col := PackedVector4Array()
	pos.append(Vector4(island.campfire_pos.x, island.campfire_pos.y + 0.45, island.campfire_pos.z, 1.8))
	col.append(Vector4(1.0, 0.55, 0.2, 1.0))
	pos.append(Vector4(island.beacon_pos.x, island.beacon_pos.y, island.beacon_pos.z, 4.0))
	col.append(Vector4(1.0, 0.86, 0.58, 1.0))
	for l: Array in island.lamps:
		if pos.size() >= 12:
			break
		var lp: Vector3 = l[0]
		pos.append(Vector4(lp.x, lp.y, lp.z, 0.7 if l[1] == "path" else 1.1))
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
	refl.scale = 0.35 if l == 0 else (0.22 if l == 1 else 0.18)
	refl.every = 1 if l == 0 else (2 if l == 1 else 3)
	refl.set_enabled(l < 2)
	island.water_mat.set_shader_parameter("refl_on", 1.0 if l < 2 else 0.0)
	sun.shadow_enabled = l < 3

func _apply_mq_materials() -> void:
	if island and island.water_mat:
		island.water_mat.set_shader_parameter("cheap", mq.water_cheap)
	if island and island.leaf_mat:
		island.leaf_mat.set_shader_parameter("near_fade", mq.leaf_near_fade)
	_scale_particles(mq.particle_mul)

func _scale_particles(mul: float) -> void:
	for n in get_tree().get_nodes_in_group("v27_particles") if get_tree() else []:
		if n is CPUParticles3D:
			var p := n as CPUParticles3D
			if not p.has_meta("base_amount"):
				p.set_meta("base_amount", p.amount)
			p.amount = maxi(1, int(round(float(p.get_meta("base_amount")) * mul)))

## FPS label + desktop reflection auto-drop (mobile ladder is MobileQuality.watch_frame).
func _watch_fps(delta: float) -> void:
	fps_t += delta
	fps_n += 1
	if fps_t < 2.0:
		return
	fps_avg = fps_n / fps_t
	fps_t = 0.0
	fps_n = 0
	fps_low = fps_low + 1 if fps_avg < 26.0 else 0
	if (not mq.mobile) and refl_auto and not demo_mode and gt > 5.0 and fps_low >= 2 and refl_level < 3:
		_set_refl_level(refl_level + 1)
		fps_low = 0
	if lbl_fps:
		lbl_fps.text = "%.0f fps · 倒影 %s · 画质 %s" % [
			fps_avg, ["高", "低", "关", "关 · 无阴影"][refl_level], mq.tier_name()]
		var dc := Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME
		var vt := Viewport.RENDER_INFO_TYPE_VISIBLE
		print("FPS %.1f refl %d tier %d night %d draws %d+%d scale %.2f size %s" % [
			fps_avg, refl_level, mq.tier, int(night_on),
			get_viewport().get_render_info(vt, dc),
			refl.vp.get_render_info(vt, dc) if refl_level < 2 else 0,
			get_viewport().scaling_3d_scale, str(refl.vp.size)])

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
	boy.stance = "stand"
	for line in sim_sweeps():
		print("SIM sweep ", line)
	print("SIM obstacles=%d palms=%d" % [island.obstacles.size(), island.palm_spots.size()])
	# gait stress test (dev/ is not exported, so only where the sources are)
	if ResourceLoader.exists("res://dev/gait_probe.gd"):
		for line in load("res://dev/gait_probe.gd").stress(self):
			print("SIM ", line)
	if ResourceLoader.exists("res://dev/hat_probe.gd"):
		var hs: Array = load("res://dev/hat_probe.gd").sim(self)
		for line: String in hs[0]:
			print("SIM ", line)
		print("SIM hat stays on the head: %s (worst offset from its seat %.3f mm)" % ["yes" if hs[2] else "NO", float(hs[1]) * 1000.0])
	_walk_metrics_report()

## gait kinematics at the walking and running speeds (dev/walk_metrics.gd)
func _walk_metrics_report() -> void:
	if not ResourceLoader.exists("res://dev/walk_metrics.gd"):
		return
	# Tripo Mixamo bone names don't match the procedural game_engine profile walk_metrics expects
	if boy.meta.get("tripo", false):
		print("SIM gait metrics skipped — Tripo Mixamo (no game_engine bone map)")
		return
	for sp: Array in [["stroll", 0.55], ["walk 0.85", 0.85], ["walk", 1.15], ["run", 2.7]]:
		var r: Array = load("res://dev/walk_metrics.gd").measure(self, float(sp[1]))
		for line: String in r[0]:
			print("SIM gait %s  %s" % [sp[0], line])

func _sim_block() -> void:
	aim_yaw = 0.0
	aim_tilt = TILT_BEST
	for pw in [0.5, 0.7, 0.85, 1.0]:
		for pitch in [0.0, 5.0, 10.0]:
			power = pw
			aim_pitch = pitch
			var r := simulate(_hand_pos(), _initial_velocity(), launch_spin(pw), aim_tilt)
			print("SIM power=%.2f pitch=%4.1f skips=%2d dist=%5.1f entry=%4.1f" % [pw, pitch, r["skips"], r["dist"], r["entry"]])

## one swept throw setting from the standing release: {skips, dist, entry, why}
func sim_throw(pw: float, el: float, tilt: float, s: float, stance := "stand") -> Dictionary:
	var keep := [boy.stance, power, aim_pitch, aim_yaw]
	boy.stance = stance
	power = pw
	aim_pitch = el
	aim_yaw = 0.0
	var r := simulate(_hand_pos(), _initial_velocity(), s, tilt)
	boy.stance = keep[0]; power = keep[1]; aim_pitch = keep[2]; aim_yaw = keep[3]
	return r

## the angle sweeps: launch elevation, stone tilt and spin each change the skips (full power, standing)
func sim_sweeps() -> Array[String]:
	var out: Array[String] = []
	for row: Array in [["elevation", [-5.0, 0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0]], ["tilt", [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0]],
			["spin", [0.2, 0.4, 0.6, 0.8, 1.0]], ["power", [0.2, 0.4, 0.6, 0.8, 1.0]]]:
		for x: float in row[1]:
			var r: Dictionary
			match row[0]:
				"elevation": r = sim_throw(1.0, x, TILT_BEST, 1.0)
				"tilt": r = sim_throw(1.0, 4.0, x, 1.0)
				"spin": r = sim_throw(1.0, 4.0, TILT_BEST, x)
				_: r = sim_throw(x, 4.0, TILT_BEST, 1.0)
			out.append("%-9s %5.1f  skips=%2d  dist=%5.1f m  entry=%4.1f deg  %s" % [row[0], x, r["skips"], r["dist"], r["entry"],
				("sank: " + str(r["why"])) if r["why"] != "slow" or r["skips"] == 0 else "ran out of speed"])
	return out

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
	_cam_slide = 0.0
	_cam_slide_want = 0.0
	_cam_arm_k = 1.0
	_cam_arm_want = 1.0
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

## v14 stills: the rowboat moored by the dock, from the sea, low over the water, from the dock and above,
## far enough out to see its reflection, and in the game camera; day and night
func _v14_sequence(pre: String) -> void:
	var bp := Vector3(2.3, 0.0, (island.dock_start_z + island.dock_end_z) * 0.5 - 1.0)
	var c := bp + Vector3(0, 0.1, 0)
	demo_nocut = true
	for night in [false, true]:
		var tag := "night" if night else "day"
		_place(Vector3(0, 0, island.dock_start_z - 1.0), PI)
		if night:
			_toggle_night()
			await _wait(2.9)
		for sh: Array in [[c, PI * 0.5 + 0.25, 0.12, 4.6, "95_%s_boat_side"], [c, 0.55, 0.07, 3.8, "96_%s_boat_bow_low"],
				[c, PI - 0.7, 0.22, 4.2, "97_%s_boat_stern"], [c, -PI * 0.5 + 0.35, 0.72, 3.3, "98_%s_boat_from_dock"],
				[c, PI * 0.5, 1.35, 4.2, "99_%s_boat_top"], [c, PI * 0.5 + 0.6, 0.05, 9.0, "99_%s_boat_far_reflection"]]:
			var cy: float = sh[1]
			_fixed_cam(sh[0], cy, sh[2], sh[3])
			await _wait(0.5)
			_shot(pre + (sh[4] as String) % tag)
		# the beached boat on the sand shares the hull
		var bb := island.shore_pt(-0.75, 1.6) + Vector3(0, 0.3, 0)
		var bo := Island.dir_at(-0.75)
		for sh: Array in [[bb, atan2(bo.x, bo.z) + 0.9, 0.3, 4.2, "99_%s_beached_boat"], [bb, atan2(bo.x, bo.z) - 0.4, 0.95, 3.6, "99_%s_beached_boat_above"]]:
			var cy: float = sh[1]
			_fixed_cam(sh[0], cy, sh[2], sh[3])
			await _wait(0.5)
			_shot(pre + (sh[4] as String) % tag)
		_place(Vector3(0.75, 0, bp.z - 0.3), -PI * 0.5)
		_free_cam()
		_snap_explore_cam()
		await _wait(1.2)
		_shot(pre + "99_%s_boat_game_view" % tag)
		if night:
			_toggle_night()
			await _wait(2.9)
	demo_nocut = false
	_free_cam()

## A scripted swipe through the real gesture code: the finger goes down at `from`, slides by `to` (short-side
## units) over `sec`, rests `hold` s (shot `shot` then), and lets go - after a quick flick on along the swipe,
## or slowly.
func _demo_swipe(from: Vector2, to: Vector2, sec: float, hold: float, flick: bool, shot := "") -> void:
	var u := _swipe_unit()
	_swipe_press(from, gt)
	var t0 := gt
	while gt - t0 < sec:
		_swipe_move(from + to * u * smoothstep(0.0, 1.0, (gt - t0) / sec), gt)
		await get_tree().process_frame
	var t1 := gt
	while gt - t1 < hold:
		_swipe_move(from + to * u, gt)
		await get_tree().process_frame
	if shot != "":
		_shot(shot)
	if not flick:
		_swipe_release(from + to * u, gt)
		return
	# the finger leaves the glass still moving: the release comes with the last move
	var d := to.normalized() * u * 0.32
	for k in range(1, 4):
		await get_tree().process_frame
		_swipe_move(from + to * u + d * (k / 3.0), gt)
	_swipe_release(from + to * u + d, gt)

func _demo_wait_ready(shots: Array) -> void:
	while state == State.THROWING:
		await get_tree().process_frame
	if shots.size() > 0 and shots[0] != "":
		await _wait(0.12)
		_shot(shots[0])
	fly_t = 0.0
	while state == State.FLYING and skips < 3:
		await get_tree().process_frame
	await _wait(0.25)
	if shots.size() > 1 and shots[1] != "":
		_shot(shots[1])
	while state != State.READY:
		await get_tree().process_frame
	await _wait(0.9)
	if shots.size() > 2 and shots[2] != "":
		_shot(shots[2])
	await _wait(1.6)

## the right shoulder (between the clavicle end and the arm joint), in the world
func _shoulder_pos(side := "r") -> Vector3:
	var sk := boy.skel
	var a := sk.get_bone_global_pose(sk.find_bone("upperarm_" + side)).origin
	var c := sk.get_bone_global_pose(sk.find_bone("clavicle_" + side)).origin
	return sk.global_transform * a.lerp(c, 0.25)

## v16: shoulder close-ups in daylight - rest pose all round, arm raised, the throws, walk / run, then the
## hammock and the towel (camera yaw relative to his facing: 0 behind, PI in front, +PI/2 his right)
func _v16_sequence(pre: String) -> void:
	_place(Vector3(0.0, 0, island.dock_end_z + 1.6), PI * 0.5)
	await _wait(0.6)
	demo_nocut = true
	ui_root.visible = false
	var k := float(_opt("shdist", "1.0"))
	var y0 := player.rotation.y
	for s: Array in [["rest_front", "idle", 0.0, 0.3, PI - 0.15, 0.05, 0.75], ["rest_34", "idle", 0.0, 0.3, PI * 0.72, 0.15, 0.6],
			["rest_side", "idle", 0.0, 0.3, PI * 0.5, 0.06, 0.6], ["rest_back34", "idle", 0.0, 0.3, PI * 0.28, 0.2, 0.6],
			["rest_back", "idle", 0.0, 0.3, 0.1, 0.12, 0.75], ["rest_top", "idle", 0.0, 0.3, PI * 0.6, 0.85, 0.6],
			["raise_front", "cheer", 1.0, 0.45, PI * 0.8, 0.1, 0.8], ["raise_back", "cheer", 1.0, 0.45, PI * 0.25, 0.2, 0.8],
			["throw_windup", "charge", 1.0, 0.3, PI * 0.4, 0.15, 0.85], ["throw_windup_back", "charge", 1.0, 0.3, 0.2, 0.25, 0.85],
			["throw_release", "release", 1.0, 0.3, PI * 0.75, 0.12, 0.85], ["throw_follow", "follow", 1.0, 0.3, 0.3, 0.2, 0.9],
			["crouch_windup", "charge_c", 1.0, 0.3, PI * 0.4, 0.2, 0.85], ["crouch_release", "release_c", 1.0, 0.3, PI * 0.75, 0.15, 0.85],
			["walk", "walk", 0.25, 0.25, PI * 0.55, 0.1, 0.75], ["run", "run", 0.2, 0.2, PI * 0.6, 0.1, 0.8]]:
		player.rotation.y = y0
		boy.debug_pose(s[1], s[2], s[3])
		await get_tree().process_frame
		_fixed_cam(_shoulder_pos(), y0 + float(s[4]), s[5], float(s[6]) * k)
		await _wait(0.3)
		_shot(pre + "v16_" + s[0])
	boy.frozen = false
	_free_cam()
	demo_nocut = false
	# lying down: the hammock, then the towel
	var hs := _hammock_spot()
	var bed: Vector3 = hs[0]
	var side: Vector3 = hs[2]
	_place(bed + side * 1.2, atan2(side.x, side.z))
	_begin_rest("sleep")
	while rest_phase < 4:
		await get_tree().process_frame
	await _wait(1.0)
	demo_nocut = true
	_fixed_cam(_shoulder_pos(), atan2(side.x, side.z) + 0.3, 0.7, 0.9)
	await _wait(0.3)
	_shot(pre + "v16_hammock")
	demo_nocut = false
	_free_cam()
	_wake()
	while mode != Mode.EXPLORE:
		await get_tree().process_frame
	var td := island.towel_dir
	var sd := td.cross(Vector3.UP).normalized()
	_place(island.towel_pos + sd * 1.3 + td * 0.4, atan2(sd.x, sd.z))
	_begin_rest("sun")
	while rest_phase < 4:
		await get_tree().process_frame
	await _wait(1.0)
	demo_nocut = true
	_fixed_cam(_shoulder_pos(), atan2(sd.x, sd.z) + 0.4, 0.75, 0.9)
	await _wait(0.3)
	_shot(pre + "v16_sun")
	demo_nocut = false
	ui_root.visible = true
	_free_cam()

## v21 video: the camera on his face (head bone, smoothed), yaw relative to his facing
func _face_cam(yaw: float, pitch: float, dist: float) -> void:
	var h := _bone_pos("head", 0.03)
	face_cam_tgt = h if face_cam_tgt == Vector3.INF else face_cam_tgt.lerp(h, 0.2)
	_fixed_cam(face_cam_tgt, player.rotation.y + yaw, pitch, dist)

func _follow_head(dur: float, yaw: float, pitch: float, dist: float, yaw_end := INF) -> void:
	var t0 := gt
	while gt - t0 < dur:
		_face_cam(yaw if yaw_end == INF else lerpf(yaw, yaw_end, (gt - t0) / dur), pitch, dist)
		await get_tree().process_frame

## a bone's position in the world, raised by `up` (m) along the world up axis
func _bone_pos(bone: String, up := 0.0) -> Vector3:
	var sk := boy.skel
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin + Vector3(0, up, 0)

## v17 close-ups in the game's light: the hair (front / side / back / three-quarter / top, with and without
## the hat, day and night, the hammock and the towel, the water reflection) and the clothes (front / side /
## back, standing, walking, running, the throws, day and night). part "" = all, "hair" or "clothes".
## Camera yaw is relative to his facing: 0 behind him, PI in front, +PI/2 his right.
func _v17_sequence(pre: String, part: String) -> void:
	_place(Vector3(0.0, 0, island.dock_end_z + 1.6), PI * 0.5)
	await _wait(0.6)
	demo_nocut = true
	ui_root.visible = false
	var y0 := player.rotation.y
	var k := float(_opt("hdist", "1.0"))
	for night in [false, true]:
		var tag := "night" if night else "day"
		if night:
			_toggle_night()
			await _wait(2.9)
		if part == "" or part == "hair":
			var views := [["front", PI - 0.12, 0.06], ["34", PI * 0.75, 0.12], ["side", PI * 0.5, 0.06],
					["back34", PI * 0.25, 0.18], ["back", 0.05, 0.12], ["top", PI * 0.7, 0.8]]
			for hat_on in [true, false]:
				boy.hat.visible = hat_on
				for s: Array in views:
					if night and String(s[0]) in ["side", "back", "top"]:
						continue
					player.rotation.y = y0
					boy.debug_pose("idle", 1.0, 0.3)
					await get_tree().process_frame
					_fixed_cam(_bone_pos("head", 0.05), y0 + float(s[1]), s[2], 0.55 * k)
					await _wait(0.4)
					_shot(pre + "v17_hair_%s_%s%s" % [tag, s[0], "" if hat_on else "_nohat"])
			boy.hat.visible = true
		if part == "" or part == "clothes":
			for s: Array in [["front", "idle", 0.0, 0.3, PI - 0.1, 0.08, 1.35], ["34", "idle", 0.0, 0.3, PI * 0.72, 0.15, 1.35],
					["side", "idle", 0.0, 0.3, PI * 0.5, 0.08, 1.35], ["back", "idle", 0.0, 0.3, 0.08, 0.12, 1.35],
					["back34", "idle", 0.0, 0.3, PI * 0.28, 0.2, 1.35], ["walk", "walk", 1.0, 0.25, PI * 0.55, 0.1, 1.45],
					["run", "run", 1.0, 0.2, PI * 0.6, 0.1, 1.5], ["windup", "charge", 1.0, 0.3, PI * 0.4, 0.15, 1.5],
					["release", "release", 1.0, 0.3, PI * 0.75, 0.12, 1.5], ["crouch", "charge_c", 1.0, 0.3, PI * 0.45, 0.2, 1.4],
					["shorts_front", "idle", 0.0, 0.3, PI - 0.25, 0.1, 0.8], ["vest_close", "idle", 0.0, 0.3, PI * 0.8, 0.1, 0.75]]:
				if night and String(s[0]) in ["walk", "run", "windup", "release", "crouch", "back34"]:
					continue
				player.rotation.y = y0
				boy.debug_pose(s[1], s[2], s[3])
				await get_tree().process_frame
				var tgt := _bone_pos("spine_01", 0.0)
				if String(s[0]) == "shorts_front":
					tgt = _bone_pos("pelvis", -0.1)
				elif String(s[0]) == "vest_close":
					tgt = _bone_pos("spine_03", 0.0)
				_fixed_cam(tgt, y0 + float(s[4]), s[5], float(s[6]) * k)
				await _wait(0.4)
				_shot(pre + "v17_clothes_%s_%s" % [tag, s[0]])
		boy.frozen = false
	_toggle_night()
	await _wait(2.8)
	if part == "" or part == "hair" or part == "refl":
		# the reflection: standing at the end of the dock, seen from above the water in front of it (his
		# mirror image lands on the water a metre or so out from the dock, clear of the deck)
		_place(Vector3(0.0, 0, island.dock_end_z + 0.35), 0.0)
		await _wait(1.0)
		var hp := _bone_pos("head")
		_fixed_cam(Vector3(hp.x, 0.4, hp.z - 2.4), player.rotation.y + PI - 0.15, 0.3, 3.8 * k)
		await _wait(0.6)
		_shot(pre + "v17_hair_day_reflection")
		_free_cam()
		# lying down: hat off in the hammock and on the towel
		var hs := _hammock_spot()
		var side: Vector3 = hs[2]
		_place(hs[0] + side * 1.2, atan2(side.x, side.z))
		_begin_rest("sleep")
		while rest_phase < 4:
			await get_tree().process_frame
		await _wait(1.0)
		_fixed_cam(_bone_pos("head"), atan2(side.x, side.z) + 0.5, 0.6, 0.8 * k)
		await _wait(0.4)
		_shot(pre + "v17_hair_day_hammock")
		_free_cam()
		_wake()
		while mode != Mode.EXPLORE:
			await get_tree().process_frame
		var td := island.towel_dir
		var sd := td.cross(Vector3.UP).normalized()
		_place(island.towel_pos + sd * 1.3 + td * 0.4, atan2(sd.x, sd.z))
		_begin_rest("sun")
		while rest_phase < 4:
			await get_tree().process_frame
		await _wait(1.0)
		_fixed_cam(_bone_pos("head"), atan2(sd.x, sd.z) + 0.6, 0.6, 0.8 * k)
		await _wait(0.4)
		_shot(pre + "v17_hair_day_sun")
		_free_cam()
		_wake()
		while mode != Mode.EXPLORE:
			await get_tree().process_frame
	demo_nocut = false
	ui_root.visible = true
	_free_cam()

## v18 close-ups of the four v17 leftovers: the hair in the hat brim's shadow (day, and night by the lamp),
## the hair card edges very close up, the back of the left armhole (tank top edge under the vest) and the
## vest's sides under the arms. Camera yaw is relative to his facing: 0 behind him, PI in front, +PI/2 his right.
func _v18_sequence(pre: String) -> void:
	_place(Vector3(0.0, 0, island.dock_end_z + 1.6), PI * 0.5)
	await _wait(0.6)
	demo_nocut = true
	ui_root.visible = false
	var y0 := player.rotation.y
	# [name, pose, p, tt, cam yaw, pitch, dist, bone, up, hat, night]
	var shots := [
		["brim_front", "idle", 1.0, 0.3, PI - 0.12, 0.02, 0.4, "head", 0.03, true, false],
		["brim_34", "idle", 1.0, 0.3, PI * 0.75, 0.05, 0.4, "head", 0.03, true, false],
		["brim_side", "idle", 1.0, 0.3, PI * 0.5, 0.02, 0.38, "head", 0.03, true, false],
		["brim_back34", "idle", 1.0, 0.3, PI * 0.25, 0.08, 0.42, "head", 0.03, true, false],
		["brim_l34", "idle", 1.0, 0.3, -PI * 0.7, 0.04, 0.4, "head", 0.03, true, false],
		["edge_side", "idle", 1.0, 0.3, PI * 0.5, 0.05, 0.2, "head", 0.06, false, false],
		["edge_back", "idle", 1.0, 0.3, 0.1, 0.15, 0.2, "head", 0.06, false, false],
		["edge_fringe", "idle", 1.0, 0.3, PI - 0.35, 0.0, 0.2, "head", 0.0, true, false],
		["armhole_idle", "idle", 1.0, 0.3, -PI * 0.2, 0.1, 0.32, "upperarm_l", -0.03, true, false],
		["armhole_charge", "charge", 0.6, 0.3, -PI * 0.2, 0.1, 0.34, "upperarm_l", -0.03, true, false],
		["armhole_cheer", "cheer", 1.0, 1.0, -PI * 0.15, 0.05, 0.34, "upperarm_l", -0.05, true, false],
		["armhole_in_charge", "charge", 0.6, 0.3, -PI * 0.62, 0.12, 0.26, "upperarm_l", -0.07, true, false],
		["armhole_in_crouch", "charge_c", 0.6, 0.3, -PI * 0.62, 0.12, 0.26, "upperarm_l", -0.07, true, false],
		["underarm_l_idle", "idle", 1.0, 0.3, -PI * 0.5, 0.05, 0.42, "spine_03", 0.08, true, false],
		["underarm_l_cheer", "cheer", 1.0, 1.0, -PI * 0.5, 0.05, 0.42, "spine_03", 0.08, true, false],
		["underarm_r_cheer", "cheer", 1.0, 1.0, PI * 0.5, 0.05, 0.42, "spine_03", 0.08, true, false],
		["underarm_l_charge", "charge", 0.6, 0.3, -PI * 0.45, 0.05, 0.45, "spine_03", 0.08, true, false],
		["underarm_r_walk", "walk", 1.0, 0.3, PI * 0.5, 0.05, 0.45, "spine_03", 0.08, true, false],
		["brim_34", "idle", 1.0, 0.3, PI * 0.75, 0.05, 0.4, "head", 0.03, true, true],
		["brim_front", "idle", 1.0, 0.3, PI - 0.12, 0.02, 0.4, "head", 0.03, true, true],
		["underarm_l_cheer", "cheer", 1.0, 1.0, -PI * 0.5, 0.05, 0.42, "spine_03", 0.08, true, true],
	]
	for s: Array in shots:
		if not String(s[0]).begins_with(_opt("only")):
			continue
		if bool(s[10]) != night_on:
			_toggle_night()
			await _wait(2.9)
		boy.hat.visible = bool(s[9])
		player.rotation.y = y0
		boy.debug_pose(s[1], s[2], s[3])
		await get_tree().process_frame
		_fixed_cam(_bone_pos(s[7], s[8]), y0 + float(s[4]), s[5], s[6])
		await _wait(0.4)
		_shot(pre + "v18_%s_%s" % ["night" if night_on else "day", s[0]])
	boy.hat.visible = true
	boy.frozen = false
	if night_on:
		_toggle_night()
	demo_nocut = false
	ui_root.visible = true
	_free_cam()

## v19 close-ups: the nape tips, the card edges up close and edge-on, the vest underarm folds with the arms
## raised (cheer, release, wind-up, sunbathing), and the hair at night
func _v19_sequence(pre: String) -> void:
	_place(Vector3(0.0, 0, island.dock_end_z + 1.6), PI * 0.5)
	await _wait(0.6)
	demo_nocut = true
	ui_root.visible = false
	var y0 := player.rotation.y
	# [name, pose, p, tt, cam yaw, pitch, dist, bone, up, hat, night]
	var shots := [] if _opt("ropeonly") == "1" else [
		["nape_back34", "idle", 1.0, 0.3, PI * 0.25, 0.08, 0.42, "head", 0.03, true, false],
		["nape_back", "idle", 1.0, 0.3, 0.05, 0.05, 0.36, "head", 0.0, true, false],
		["nape_close", "idle", 1.0, 0.3, PI * 0.15, 0.02, 0.24, "head", -0.03, true, false],
		["nape_nohat", "idle", 1.0, 0.3, PI * 0.2, 0.1, 0.4, "head", 0.03, false, false],
		["edge_side", "idle", 1.0, 0.3, PI * 0.5, 0.05, 0.2, "head", 0.06, false, false],
		["edge_back", "idle", 1.0, 0.3, 0.1, 0.15, 0.2, "head", 0.06, false, false],
		["edge_top", "idle", 1.0, 0.3, PI * 0.6, 0.02, 0.16, "head", 0.1, false, false],
		["edge_fringe", "idle", 1.0, 0.3, PI - 0.35, 0.0, 0.2, "head", 0.0, true, false],
		["fold_cheer_front", "cheer", 1.0, 1.0, PI - 0.25, 0.05, 0.6, "spine_03", 0.06, true, false],
		["fold_cheer_side", "cheer", 1.0, 1.0, PI * 0.5, 0.05, 0.45, "spine_03", 0.08, true, false],
		["fold_cheer_back", "cheer", 1.0, 1.0, 0.2, 0.05, 0.6, "spine_03", 0.06, true, false],
		["fold_release_front", "release", 1.0, 0.3, PI - 0.3, 0.05, 0.65, "spine_03", 0.06, true, false],
		["fold_charge_back", "charge", 0.6, 0.3, 0.0, 0.08, 0.85, "spine_03", 0.0, true, false],
		["fold_sun", "sun", 1.0, 0.3, PI * 0.5, 0.75, 1.0, "spine_03", 0.0, false, false],
		["fold_sun_close", "sun", 1.0, 0.3, PI * 0.3, 0.5, 0.55, "upperarm_r", 0.0, false, false],
		["night_brim_34", "idle", 1.0, 0.3, PI * 0.75, 0.05, 0.4, "head", 0.03, true, true],
		["night_brim_front", "idle", 1.0, 0.3, PI - 0.12, 0.02, 0.4, "head", 0.03, true, true],
		["night_back34", "idle", 1.0, 0.3, PI * 0.25, 0.08, 0.42, "head", 0.03, true, true],
		["night_side", "idle", 1.0, 0.3, -PI * 0.5, 0.02, 0.4, "head", 0.03, true, true],
		["night_nohat", "idle", 1.0, 0.3, PI * 0.7, 0.08, 0.42, "head", 0.05, false, true],
	]
	for s: Array in shots:
		if not String(s[0]).begins_with(_opt("only")):
			continue
		if bool(s[10]) != night_on:
			_toggle_night()
			await _wait(2.9)
		boy.hat.visible = bool(s[9])
		player.rotation.y = y0
		boy.debug_pose(s[1], s[2], s[3])
		await get_tree().process_frame
		_fixed_cam(_bone_pos(s[7], s[8]), y0 + float(s[4]), s[5], s[6])
		await _wait(0.4)
		_shot(pre + "v19_%s" % s[0])
	boy.hat.visible = true
	boy.frozen = false
	if night_on:
		_toggle_night()
		await _wait(2.9)
	# the mooring line's dock end while the boat bobs: two frames 1.3 s apart, same camera
	# (and how far that end would wander if it rode on the boat, as it did up to v18)
	_fixed_cam(island.boat_tie, 0.6, 0.3, 1.0)
	var drift := 0.0
	for k in 3:
		var t0 := gt
		while gt - t0 < 1.3:
			var rigid: Vector3 = island.dock_boat.transform * (island.boat_rest.affine_inverse() * island.boat_tie)
			drift = maxf(drift, (rigid - island.boat_tie).length())
			await get_tree().process_frame
		_shot(pre + "v19_rope_%d" % k)
	print("V19 mooring line dock end: rides the boat up to %.1f cm off the knot (pinned since v19)" % (drift * 100.0))
	demo_nocut = false
	ui_root.visible = true
	_free_cam()

## v20: the straw hat stays on his head. part "lie": the real hammock / towel / bench / log rest from the
## game (lying down, lying, close-ups at the head, getting up); part "pose": close-ups of the hat on the hair
## through walk / run / the throws / cheer / oops. part "" = both.
func _v20_sequence(pre: String, part: String) -> void:
	if part == "" or part == "lie":
		var hs := _hammock_spot()
		var td := island.towel_dir
		var sd := td.cross(Vector3.UP).normalized()
		for spec: Array in [["hammock", "sleep", hs[0] + hs[2] * 1.6], ["towel", "sun", island.towel_pos + sd * 1.4], ["bench", 0, null], ["log", 1, null]]:
			var nm: String = spec[0]
			if _opt("only") != "" and not nm.begins_with(_opt("only")):
				continue
			_free_cam()
			if spec[1] is String:
				_place(spec[2], 0.0)
				await _wait(0.3)
				_begin_rest(spec[1])
				while rest_phase != 3:
					await get_tree().process_frame
			else:
				var st: Dictionary = island.seats[spec[1]]
				var face: Vector3 = st["face"]
				_place(_blocked_by((st["approach"] as Vector3) + face * 0.7), 0.0)
				await _wait(0.3)
				_on_action()
				while rest_phase != 4:
					await get_tree().process_frame
				await _wait(0.5)
				_lie_down()
			var dur := SEAT_LIE_DUR if rest_kind == "seat" else 1.0
			# across him: from the open side (in front of a seat)
			var lat: Vector3 = seat_face if rest_kind == "seat" else rest_side
			await _wait(dur * 0.55)
			_shot(pre + "v20_%s_1_lying_down" % nm)
			_fixed_cam((boy.parts["head"] as Node3D).global_position, atan2(lat.x, lat.z), 0.3, 1.1)
			await get_tree().process_frame
			_shot(pre + "v20_%s_1b_lying_down_close" % nm)
			_free_cam()
			while rest_phase != 4:
				await get_tree().process_frame
			await _wait(1.2)
			_shot(pre + "v20_%s_2_lie" % nm)
			var head: Vector3 = (boy.parts["head"] as Node3D).global_position
			var hd := rest_lie_b.y
			_fixed_cam(head, atan2(lat.x, lat.z), 0.3, 0.95)
			await _wait(0.3)
			_shot(pre + "v20_%s_3_close_side" % nm)
			_fixed_cam(head, atan2(hd.x, hd.z) + 0.5, 0.12, 0.8)
			await _wait(0.3)
			_shot(pre + "v20_%s_4_close_head_end" % nm)
			_free_cam()
			_wake()
			while rest_phase != 5 and rest_phase != 6:
				await get_tree().process_frame
			await _wait(dur * 0.45)
			_shot(pre + "v20_%s_5_getting_up" % nm)
			while mode != Mode.EXPLORE:
				await get_tree().process_frame
			await _wait(0.3)
	if part == "" or part == "pose":
		_place(Vector3(0.0, 0, island.dock_end_z + 1.6), PI * 0.5)
		await _wait(0.6)
		demo_nocut = true
		ui_root.visible = false
		var y0 := player.rotation.y
		# [name, pose, p, tt, cam yaw, pitch, dist]
		var shots := [
			["idle_side", "idle", 1.0, 0.3, PI * 0.5, 0.05, 0.55],
			["idle_front", "idle", 1.0, 0.3, PI - 0.3, 0.05, 0.55],
			["walk", "walk", 1.0, 0.3, PI * 0.6, 0.05, 0.6],
			["run", "run", 1.0, 0.15, PI * 0.6, 0.05, 0.6],
			["charge", "charge", 1.0, 0.3, PI * 0.35, 0.1, 0.7],
			["release", "release", 1.0, 0.3, PI * 0.7, 0.05, 0.7],
			["follow", "follow", 1.0, 0.3, PI * 0.75, 0.05, 0.7],
			["crouch_release", "release_c", 1.0, 0.3, PI * 0.7, 0.1, 0.7],
			["cheer", "cheer", 1.0, float(_opt("cheer_t", "1.0")), PI - 0.4, 0.05, 0.7],
			["oops", "oops", 1.0, float(_opt("oops_t", "0.8")), PI - 0.3, 0.05, 0.6],
		]
		for s: Array in shots:
			if not Array(_opt("only").split(",")).any(func(o: String) -> bool: return String(s[0]).begins_with(o)):
				continue
			player.rotation.y = y0
			boy.debug_pose(s[1], s[2], s[3])
			await get_tree().process_frame
			_fixed_cam(_bone_pos("head", 0.04), y0 + float(s[4]), s[5], s[6])
			await _wait(0.4)
			_shot(pre + "v20_pose_%s" % s[0])
		boy.frozen = false
		demo_nocut = false
		ui_root.visible = true
		_free_cam()

## v21 face: close-ups (front / three-quarter / side), the expressions, the sleeping face (hat hidden: it lies
## over his face then), the game camera with him turned toward it; then at night by a torch
func _v21_sequence(pre: String, ver := "v21", dk := 1.0) -> void:
	demo_nocut = true
	var ex0 := [ex_dist, ex_pitch]
	for night: bool in [false, true]:
		var tag := "night" if night else "day"
		var p := Vector3(0.0, 0, island.dock_end_z + 1.6)
		var y0 := PI * 0.5
		if night:
			_toggle_night()
			var c := island.campfire_pos
			var tp := island.torches[0].global_position
			var out := Vector3(tp.x - c.x, 0, tp.z - c.z).normalized()
			p = Vector3(tp.x, 0, tp.z) - out * 0.8 + out.cross(Vector3.UP) * 0.35
			y0 = atan2(out.x, out.z) + 0.4
			await _wait(2.9)
		_place(p, y0)
		await _wait(0.6)
		ui_root.visible = false
		# [name, pose, p, tt, cam yaw, pitch, dist]
		var shots := [["front", "idle", 1.0, 0.3, PI, 0.03, 0.4], ["34", "idle", 1.0, 0.3, PI - 0.75, 0.04, 0.4],
			["side", "idle", 1.0, 0.3, PI * 0.5, 0.03, 0.42], ["up", "idle", 1.0, 0.3, PI - 0.35, 0.75, 0.55]]
		if not night:
			shots += [["focus", "charge", 1.0, 0.3, PI - 0.6, -0.25, 0.45], ["cheer", "cheer", 1.0, 1.0, PI - 0.3, 0.04, 0.5],
				["oops", "oops", 1.0, 0.8, PI - 0.25, -0.3, 0.45], ["sleep", "sleep", 1.0, 0.3, PI - 0.4, 0.04, 0.42],
				["closed", "idle", 1.0, 0.3, PI - 0.4, 0.04, 0.42]]
		if ver != "v21":
			shots += [["body", "idle", 1.0, 0.3, PI - 0.3, 0.08, 1.6 / dk], ["bodyside", "idle", 1.0, 0.3, PI * 0.5, 0.08, 1.6 / dk]]
		for s: Array in shots:
			if not Array(_opt("only").split(",")).any(func(o: String) -> bool: return String(s[0]).begins_with(o)):
				continue
			player.rotation.y = y0
			boy.debug_pose(s[1], s[2], s[3])
			if s[0] == "closed":
				boy.blink_t = 0.08
				boy._update_face(0.0)
			boy.hat.visible = s[0] != "sleep"
			if s[0] == "sleep":
				boy.glasses.visible = false
			await get_tree().process_frame
			var tgt := _bone_pos("head", 0.03)
			if String(s[0]).begins_with("body"):
				tgt = _bone_pos("pelvis", 0.0) + Vector3(0, 0.12, 0)
			_fixed_cam(tgt, y0 + float(s[4]), s[5], float(s[6]) * dk)
			await _wait(0.3)
			_shot(pre + "%s_%s_%s" % [ver, tag, s[0]])
			boy.hat.visible = true
		boy.frozen = false
		# the game camera, him turned toward it
		_free_cam()
		ui_root.visible = true
		_place(p, y0)
		ex_yaw = face_yaw + PI
		var ec := _explore_cam()
		cam_target = ec[0]; cam_yaw = ec[1]; cam_pitch = ec[2]; cam_dist = ec[3]
		await _wait(1.2)
		_shot(pre + "%s_%s_game" % [ver, tag])
		# pinched in and dragged lower, as a player does to look at him
		ex_dist = 3.0
		ex_pitch = 0.55
		ec = _explore_cam()
		cam_target = ec[0]; cam_yaw = ec[1]; cam_pitch = ec[2]; cam_dist = ec[3]
		await _wait(0.8)
		_shot(pre + "%s_%s_game_zoom" % [ver, tag])
		ex_dist = ex0[0]
		ex_pitch = ex0[1]
		if night:
			_toggle_night()
			await _wait(2.9)
	demo_nocut = false

## v15: aiming by swipe - the pad and angle sliders, aiming left / right (arrow, preview, readout, the chest
## turning first), cancel, a flicked throw, a too-steep launch, a too-flat stone, a slow release (no spin)
func _v15_sequence(pre: String) -> void:
	_place(Vector3(0.0, 0, island.dock_end_z + 1.6), 0.0)
	await _wait(0.4)
	_enter_throw()
	await _wait(1.8)
	_shot(pre + "v15_1_ready")
	var c := throw_pad.pad_c
	_swipe_press(c, gt)
	for k in 12:
		_swipe_move(c + Vector2(-0.2, -0.3) * _swipe_unit() * (k + 1) / 12.0, gt)
		await get_tree().process_frame
	await _wait(0.9)
	_shot(pre + "v15_2_aim_left")
	if not portrait_demo:
		_fixed_cam(player.global_position + Vector3(0, 0.75, 0), aim_yaw + 2.2, 0.25, 2.6)
		await _wait(0.2)
		_shot(pre + "v15_2b_aim_left_body")
		_free_cam()
	for k in 10:
		_swipe_move(c + Vector2(-0.2, -0.3).lerp(Vector2(0.02, 0.1), (k + 1) / 10.0) * _swipe_unit(), gt)
		await get_tree().process_frame
	await _wait(0.3)
	_shot(pre + "v15_3_cancel")
	_swipe_release(c + Vector2(0.02, 0.1) * _swipe_unit(), gt)
	await _wait(1.2)
	await _demo_swipe(c, Vector2(0.17, -0.4), 0.5, 0.8, true, pre + "v15_4_aim_right")
	await _demo_wait_ready([pre + "v15_5_release", pre + "v15_6_skipping", pre + "v15_7_result"])
	_set_angles(28.0, 20.0)
	await _wait(0.6)
	await _demo_swipe(c, Vector2(0.0, -0.45), 0.4, 0.6, true, pre + "v15_8_steep_aim")
	await _demo_wait_ready(["", "", pre + "v15_9_steep_result"])
	_set_angles(4.0, 3.0)
	await _wait(0.6)
	await _demo_swipe(c, Vector2(-0.05, -0.45), 0.4, 0.6, true, pre + "v15_10_flat_aim")
	await _demo_wait_ready(["", "", pre + "v15_11_flat_result"])
	_set_angles(4.0, 20.0)
	await _wait(0.6)
	await _demo_swipe(c, Vector2(0.0, -0.45), 0.4, 0.8, false)
	await _demo_wait_ready(["", "", pre + "v15_12_slow_release_result"])
	if not portrait_demo:
		_toggle_night()
		await _wait(2.9)
		await _demo_swipe(c, Vector2(-0.08, -0.42), 0.5, 0.8, true, pre + "v15_13_night_aim")
		await _demo_wait_ready(["", "", ""])
		_toggle_night()
		await _wait(2.9)

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
			elif what == "v14":
				await _v14_sequence(pre)
			elif what == "v15":
				await _v15_sequence(pre)
			elif what == "v16":
				await _v16_sequence(pre)
			elif what.begins_with("v17"):
				await _v17_sequence(pre, what.substr(3).trim_prefix("_"))
			elif what == "v18":
				await _v18_sequence(pre)
			elif what == "v19":
				await _v19_sequence(pre)
			elif what.begins_with("v20"):
				await _v20_sequence(pre, what.substr(3).trim_prefix("_"))
			elif what == "v21":
				await _v21_sequence(pre)
			elif what == "v22":
				await _v21_sequence(pre, "v22", 1.2)
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

		"face21":
			# the face up close: idle with its blinks (front round to the side), a throw (focus, then the cheer),
			# an oops, by a torch at night; then the game camera with him turned toward it
			_place(Vector3(0.0, 0, island.dock_end_z + 1.6), PI * 0.5)
			await _wait(0.5)
			ui_root.visible = false
			face_cam_tgt = Vector3.INF
			await _follow_head(3.2, PI, 0.03, 0.45)
			await _follow_head(3.0, PI, 0.03, 0.45, PI * 0.5)
			await _follow_head(0.8, PI * 0.5, 0.03, 0.45)
			_enter_throw()
			await _follow_head(1.2, PI - 0.55, -0.15, 0.6)
			_begin_aim(Vector2.ZERO)
			aim_pitch = 3.0
			var ft0 := gt
			while gt - ft0 < 1.4:
				charge_t = minf((gt - ft0) / 1.2, 1.0) * 0.9 * POWER_CYCLE * 0.5
				_face_cam(PI - 0.55, -0.15, 0.6)
				await get_tree().process_frame
			charge_t = 0.9 * POWER_CYCLE * 0.5
			_throw()
			fly_t = 0.0
			while state != State.READY:
				_face_cam(PI - 0.55, -0.15, 0.6)
				await get_tree().process_frame
			if boy.anim != "react":
				boy.react("cheer")
			await _follow_head(2.4, PI - 0.4, -0.1, 0.6)
			boy.react("oops")
			await _follow_head(2.4, PI - 0.3, -0.25, 0.55)
			_leave_throw()
			var c := island.campfire_pos
			var tp := island.torches[0].global_position
			var out := Vector3(tp.x - c.x, 0, tp.z - c.z).normalized()
			night_on = true
			night_k = 1.0
			_update_night(0.0, true)
			_place(Vector3(tp.x, 0, tp.z) - out * 0.8 + out.cross(Vector3.UP) * 0.35, atan2(out.x, out.z) + 0.4)
			await get_tree().process_frame
			face_cam_tgt = Vector3.INF
			await _follow_head(4.0, PI - 0.4, 0.03, 0.45)
			night_on = false
			night_k = 0.0
			_update_night(0.0, true)
			_place(Vector3(0.0, 0, island.dock_end_z + 1.6), PI * 0.5)
			_free_cam()
			ui_root.visible = true
			ex_yaw = face_yaw + PI
			var ec := _explore_cam()
			cam_target = ec[0]; cam_yaw = ec[1]; cam_pitch = ec[2]; cam_dist = ec[3]
			await _wait(3.0)

		"hat20":
			# the hat, followed at head height: walk, sharp turns, run onto the dock, a throw and a cheer, then the
			# hammock, where his hand takes it over his face and back
			var a := island.shore_pt(-1.32, 1.4)
			var dock_foot := Vector3(0.0, 0, island.dock_start_z + 1.5)
			var d0 := (dock_foot - a).normalized()
			_place(a, atan2(-d0.x, -d0.z))
			ex_yaw = face_yaw
			_snap_cam_now()
			demo_cam = true
			demo_track = [face_yaw + PI * 0.5 + 0.5, 0.14, 2.6, 0.75, true]
			var r := Vector3(d0.z, 0, -d0.x)
			await _walk_to(a + d0 * 2.2, false, 3.0)
			await _walk_to(a + d0 * 2.2 + r * 1.6, false, 2.0)
			await _walk_to(a + d0 * 0.8 + r * 1.6, false, 2.0)
			await _walk_to(a + d0 * 2.6 + r * 0.4, false, 2.2)
			await _walk_to(dock_foot, true, 4.0)
			await _walk_to(Vector3(0.2, 0, island.dock_end_z + 1.5), true, 4.0)
			await _wait(0.4)
			_enter_throw()
			await _wait(1.0)
			demo_track = [player.rotation.y + PI * 0.5 + 0.55, 0.16, 2.6, 0.6, true]
			_begin_aim(Vector2.ZERO)
			aim_pitch = 3.0
			var t0 := gt
			while gt - t0 < 1.4:
				charge_t = minf((gt - t0) / 1.2, 1.0) * 0.9 * POWER_CYCLE * 0.5
				await get_tree().process_frame
			charge_t = 0.9 * POWER_CYCLE * 0.5
			_throw()
			fly_t = 0.0
			while state != State.READY:
				await get_tree().process_frame
			if boy.anim != "react":
				boy.react("cheer")
			await _wait(2.6)
			_leave_throw()
			var hs := _hammock_spot()
			var bed: Vector3 = hs[0]
			var side: Vector3 = hs[2]
			_place(bed + side * 2.2 + (island.hammock_b - island.hammock_a).normalized() * 0.8, atan2(side.x, side.z))
			ex_yaw = face_yaw + PI + 0.5
			_snap_cam_now()
			_free_cam()
			await _walk_to(bed + side * 1.2, false, 1.8)
			_begin_rest("sleep")
			var head: Vector3 = (boy.parts["head"] as Node3D).global_position
			_fixed_cam(bed + Vector3(0, 0.25, 0), atan2(side.x, side.z) + 0.35, 0.32, 2.4)
			while rest_phase < 4:
				await get_tree().process_frame
			await _wait(1.6)
			_wake()
			while mode != Mode.EXPLORE:
				await get_tree().process_frame
			await _wait(0.4)
			_free_cam()
			await _walk_to(head + side * 2.5, false, 2.0)
			await _wait(0.5)

		"boat14":
			# the rowboat by the dock riding the swell: from the sea, from the dock, then at night
			var bp := Vector3(2.3, 0.1, (island.dock_start_z + island.dock_end_z) * 0.5 - 1.0)
			_place(Vector3(0, 0, island.dock_start_z - 1.0), PI)
			demo_nocut = true
			_fixed_cam(bp, PI * 0.5 + 0.3, 0.1, 4.4)
			await _wait(6.0)
			_fixed_cam(bp, -PI * 0.5 + 0.35, 0.6, 3.4)
			await _wait(4.0)
			_toggle_night()
			await _wait(3.0)
			_fixed_cam(bp, PI * 0.5 + 0.3, 0.1, 4.4)
			await _wait(5.0)
			_toggle_night()
			demo_nocut = false

		"shoulder16":
			# close on the right shoulder in daylight: once round him at rest, the arms going up (cheer),
			# a standing and a crouching throw in slow motion, then a walk and a run cycle
			_place(Vector3(0.0, 0, island.dock_end_z + 1.6), PI * 0.5)
			await _wait(0.3)
			demo_nocut = true
			ui_root.visible = false
			var y0 := player.rotation.y
			var tc := float(boy.clips["throw_stand"]["t_charge"])
			var tcc := float(boy.clips["throw_crouch"]["t_charge"])
			var cl := float(boy.clips["cheer"]["length"])
			var k := float(_opt("shdist", "0.6"))
			# [pose, from, to, seconds, cam yaw from, cam yaw to, pitch, dist]
			for s: Array in [["idle", 0.0, 2.0, 5.0, PI - 0.1, 0.15, 0.12, 0.8],
					["cheer", 0.0, cl * 0.75, 3.0, PI * 0.8, PI * 0.65, 0.12, 0.9],
					["cheer", 0.0, cl * 0.75, 3.0, PI * 0.25, PI * 0.35, 0.2, 0.9],
					["charge", 0.0, 1.0 / tc * 1.15, 4.0, PI * 0.45, PI * 0.3, 0.15, 0.95],
					["charge", 0.0, 1.0 / tc * 1.15, 4.0, PI * 0.8, PI * 0.7, 0.12, 0.95],
					["charge_c", 0.0, 1.0 / tcc * 1.15, 4.0, PI * 0.45, PI * 0.6, 0.2, 0.95],
					["walk", 0.0, 2.0, 2.5, PI * 0.55, PI * 0.45, 0.1, 0.85],
					["run", 0.0, 2.0, 2.0, PI * 0.6, PI * 0.5, 0.1, 0.9]]:
				var t0 := gt
				var tgt := Vector3.ZERO
				while gt - t0 < float(s[3]):
					var u := (gt - t0) / float(s[3])
					var v := lerpf(float(s[1]), float(s[2]), u)
					player.rotation.y = y0
					match String(s[0]):
						"cheer":
							boy.debug_pose("cheer", 1.0, v)
						"charge", "charge_c":
							boy.debug_pose(s[0], v)
						"walk", "run":
							boy.debug_pose(s[0], 1.0, fmod(v, 1.0))
						_:
							boy.debug_pose("idle", 1.0, v)
					var sp := _shoulder_pos()
					tgt = sp if gt - t0 < 0.01 else tgt.lerp(sp, 0.25)
					_fixed_cam(tgt, y0 + lerpf(float(s[4]), float(s[5]), u), s[6], float(s[7]) * k)
					await get_tree().process_frame
			boy.frozen = false
			demo_nocut = false
			ui_root.visible = true
			_free_cam()

		"polish19":
			# v19 close-ups: the nape (hat on, then off and close enough to see single strands), the vest's
			# underarm folding as the arms go up, the hair at night away from the torches, the mooring line
			_place(Vector3(0.0, 0, island.dock_end_z + 1.6), PI * 0.5)
			await _wait(0.3)
			demo_nocut = true
			ui_root.visible = false
			var y0 := player.rotation.y
			var cl := float(boy.clips["cheer"]["length"])
			# [pose, from, to, seconds, cam yaw from, cam yaw to, pitch, dist, bone, up, hat, night]
			for s: Array in [["idle", 0.0, 3.0, 5.0, PI * 0.4, -PI * 0.3, 0.05, 0.38, "head", 0.0, true, false],
					["idle", 0.0, 2.0, 4.5, PI * 0.55, -PI * 0.1, 0.1, 0.22, "head", 0.04, false, false],
					["cheer", 0.0, cl * 0.75, 4.0, PI - 0.25, PI * 0.62, 0.05, 0.6, "spine_03", 0.06, true, false],
					["cheer", 0.0, cl * 0.75, 3.5, 0.1, PI * 0.35, 0.05, 0.55, "spine_03", 0.06, true, false],
					["idle", 0.0, 3.0, 5.0, PI * 0.8, PI * 0.2, 0.06, 0.42, "head", 0.03, true, true],
					["idle", 0.0, 2.0, 3.5, PI * 0.6, PI * 0.9, 0.08, 0.42, "head", 0.05, false, true]]:
				if bool(s[11]) != night_on:
					_toggle_night()
					await _wait(2.9)
				boy.hat.visible = bool(s[10])
				var t0 := gt
				var tgt := Vector3.ZERO
				while gt - t0 < float(s[3]):
					var u := (gt - t0) / float(s[3])
					var v := lerpf(float(s[1]), float(s[2]), u)
					player.rotation.y = y0
					if s[0] == "cheer":
						boy.debug_pose("cheer", 1.0, v)
					else:
						boy.debug_pose("idle", 1.0, v)
					var bp := _bone_pos(s[8], s[9])
					tgt = bp if gt - t0 < 0.01 else tgt.lerp(bp, 0.25)
					_fixed_cam(tgt, y0 + lerpf(float(s[4]), float(s[5]), u), s[6], s[7])
					await get_tree().process_frame
			boy.hat.visible = true
			_fixed_cam(island.boat_tie, 0.6, 0.3, 1.0)
			if night_on:
				_toggle_night()
				await _wait(2.9)
			await _wait(4.0)
			boy.frozen = false
			demo_nocut = false
			ui_root.visible = true
			_free_cam()

		"polish18":
			# v18 close-ups: the hair under the brim in daylight, the card edges up close (hat off), the vest's
			# underarm with the arms going up, the hems swaying through a walk and a run, a crouching throw
			_place(Vector3(0.0, 0, island.dock_end_z + 1.6), PI * 0.5)
			await _wait(0.3)
			demo_nocut = true
			ui_root.visible = false
			var y0 := player.rotation.y
			var tcc := float(boy.clips["throw_crouch"]["t_charge"])
			var cl := float(boy.clips["cheer"]["length"])
			# [pose, from, to, seconds, cam yaw from, cam yaw to, pitch, dist, bone, up, hat]
			for s: Array in [["idle", 0.0, 3.0, 6.0, PI * 0.95, PI * 0.3, 0.04, 0.42, "head", 0.03, true],
					["idle", 0.0, 2.0, 4.0, PI * 0.6, PI * 0.15, 0.08, 0.24, "head", 0.06, false],
					["cheer", 0.0, cl * 0.75, 4.0, PI * 0.5, PI * 0.38, 0.05, 0.5, "spine_03", 0.08, true],
					["walk", 0.0, 3.0, 4.0, PI * 0.6, PI * 0.4, 0.06, 1.1, "spine_01", 0.0, true],
					["run", 0.0, 3.0, 3.0, PI * 0.4, PI * 0.6, 0.06, 1.2, "spine_01", 0.0, true],
					["charge_c", 0.0, 1.0 / tcc * 1.15, 3.5, -PI * 0.3, -PI * 0.55, 0.12, 0.6, "upperarm_l", -0.05, true]]:
				boy.hat.visible = bool(s[10])
				var t0 := gt
				var tgt := Vector3.ZERO
				while gt - t0 < float(s[3]):
					var u := (gt - t0) / float(s[3])
					var v := lerpf(float(s[1]), float(s[2]), u)
					player.rotation.y = y0
					match String(s[0]):
						"cheer":
							boy.debug_pose("cheer", 1.0, v)
						"charge_c":
							boy.debug_pose(s[0], v)
						"walk", "run":
							boy.debug_pose(s[0], 1.0, fmod(v, 1.0))
						_:
							boy.debug_pose("idle", 1.0, v)
					var bp := _bone_pos(s[8], s[9])
					tgt = bp if gt - t0 < 0.01 else tgt.lerp(bp, 0.25)
					_fixed_cam(tgt, y0 + lerpf(float(s[4]), float(s[5]), u), s[6], s[7])
					await get_tree().process_frame
			boy.hat.visible = true
			boy.frozen = false
			demo_nocut = false
			ui_root.visible = true
			_free_cam()

		"outfit17":
			# close on the hair and the clothes: round his head and his body at rest, a walk, a run and a
			# crouching throw (hair / hem sway), then the same orbits at night
			_place(Vector3(0.0, 0, island.dock_end_z + 1.6), PI * 0.5)
			await _wait(0.3)
			demo_nocut = true
			ui_root.visible = false
			var y0 := player.rotation.y
			var tcc := float(boy.clips["throw_crouch"]["t_charge"])
			# [pose, from, to, seconds, cam yaw from, cam yaw to, pitch, dist, bone, up, night]
			for s: Array in [["idle", 0.0, 3.0, 6.0, PI - 0.1, -0.3, 0.1, 0.55, "head", 0.05, false],
					["idle", 0.0, 3.0, 6.0, PI * 0.9, PI * 0.05, 0.08, 1.05, "spine_01", 0.0, false],
					["walk", 0.0, 3.0, 3.0, PI * 0.65, PI * 0.4, 0.08, 1.2, "spine_01", 0.0, false],
					["run", 0.0, 3.0, 2.5, PI * 0.4, PI * 0.6, 0.08, 1.3, "spine_01", 0.0, false],
					["charge_c", 0.0, 1.0 / tcc * 1.15, 3.5, PI * 0.45, PI * 0.6, 0.15, 1.2, "spine_01", 0.0, false],
					["idle", 0.0, 3.0, 5.0, PI - 0.1, PI * 0.2, 0.1, 0.55, "head", 0.05, true],
					["idle", 0.0, 3.0, 5.0, PI * 0.9, PI * 0.3, 0.08, 1.05, "spine_01", 0.0, true]]:
				if bool(s[10]) != night_on:
					_toggle_night()
					await _wait(2.9)
				var t0 := gt
				var tgt := Vector3.ZERO
				while gt - t0 < float(s[3]):
					var u := (gt - t0) / float(s[3])
					var v := lerpf(float(s[1]), float(s[2]), u)
					player.rotation.y = y0
					match String(s[0]):
						"charge_c":
							boy.debug_pose(s[0], v)
						"walk", "run":
							boy.debug_pose(s[0], 1.0, fmod(v, 1.0))
						_:
							boy.debug_pose("idle", 1.0, v)
					var bp := _bone_pos(s[8], s[9])
					tgt = bp if gt - t0 < 0.01 else tgt.lerp(bp, 0.25)
					_fixed_cam(tgt, y0 + lerpf(float(s[4]), float(s[5]), u), s[6], s[7])
					await get_tree().process_frame
			if night_on:
				_toggle_night()
			boy.frozen = false
			demo_nocut = false
			ui_root.visible = true
			_free_cam()

		"throw15":
			# aiming by swipe on the dock: left with a flick, right with a slow release (no spin), the
			# elevation slider pushed up to a too-steep launch, then a good one straight out
			_place(Vector3(0.0, 0, island.dock_end_z + 1.6), 0.0)
			await _wait(0.3)
			_enter_throw()
			await _wait(2.2)
			var c := throw_pad.pad_c
			await _demo_swipe(c, Vector2(-0.2, -0.38), 0.8, 1.0, true)
			await _demo_wait_ready([])
			await _demo_swipe(c, Vector2(0.24, -0.36), 0.8, 1.0, false)
			await _demo_wait_ready([])
			for k in 24:
				_set_angles(lerpf(4.0, 28.0, (k + 1) / 24.0), 20.0)
				await get_tree().process_frame
			await _wait(0.5)
			await _demo_swipe(c, Vector2(0.06, -0.45), 0.6, 0.8, true)
			await _demo_wait_ready([])
			for k in 24:
				_set_angles(lerpf(28.0, 4.0, (k + 1) / 24.0), 20.0)
				await get_tree().process_frame
			await _wait(0.5)
			await _demo_swipe(c, Vector2(-0.04, -0.46), 0.6, 0.8, true)
			await _demo_wait_ready([])

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
