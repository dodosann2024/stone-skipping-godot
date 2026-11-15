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
## Stick mag to enter run / drop back to walk (hysteresis so the threshold doesn't chatter).
const RUN_STICK_ON := 0.90
const RUN_STICK_OFF := 0.82

enum Mode { EXPLORE, THROW, VIEW, REST }
enum State { READY, AIMING, THROWING, FLYING, SINKING }

var island: Island
## v37 pipeline owners (one concern each).
var ground_sys: Ground
var player_ctrl: PlayerController
var follow_cam: FollowCamera
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
var print_side := PackedFloat32Array()  # 0 left / 1 right sandal
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
## Critically-damped explore follow (look-at + yaw). Velocities in world / rad/s.
var _cam_t_vel := Vector3.ZERO
var _cam_yaw_vel := 0.0
var _cam_pitch_vel := 0.0
var _cam_dist_vel := 0.0
var _cam_pos_prev := Vector3.ZERO
var _cam_pos_init := false
var _cam_max_step_cm := 0.0
## Stick-lock orbit follow can jump on face turns; tracked separately from walk snaps.
var _cam_orbit_step_cm := 0.0
var _cam_teleport := false
## Smoothed hillside spring-arm lift (m) + final lens velocity for ≤5–8 cm/frame chase.
var _cam_hill_lift := 0.0
var _cam_hill_vel := 0.0
var _cam_pos_vel := Vector3.ZERO
## When true, explore orbit is hard-locked behind the boy — skip step clamp so a
## 180° face turn doesn't leave the lens beside him (CDP dir_sw/w off-screen).
var _cam_stick_lock := false

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
## Physics-clock body pose; _process lerps player transform for display + camera.
var _body_pos := Vector3.ZERO
var _body_pos_prev := Vector3.ZERO
var _body_yaw := 0.0
var _body_yaw_prev := 0.0
var _body_sync := false
## True until the first physics tick of a render frame — so multi-step physics
## keeps prev = pose at last display, not the mid-frame intermediate.
var _body_new_frame := true
## Camera mode blend (观景 / 固定视角 / sit-stand): ease-in-out over ~0.55 s.
var _cam_blend_t := 0.0
var _cam_blend_dur := 0.55
var _cam_blend_from_t := Vector3.ZERO
var _cam_blend_from_yaw := 0.0
var _cam_blend_from_pitch := 0.0
var _cam_blend_from_dist := 0.0
## Throttled upkeep (cutout / night omni / prints) — 10–20 Hz.
var _throttle_t := 0.0
var _cut_focus := Vector3.ZERO
var _cut_cr_f := 2.2
var _cut_cr_s := 1.7
## On-device debug HUD (?debug=1).
var dbg = null
## Debug: max |Δxz| this session (m/physics tick) and feet-vs-mesh gap (m).
var dbg_max_step := 0.0
var dbg_gnd_err := 0.0
var _orbit_smooth := Vector2.ZERO
var keys_run := false
## Sticky run gate from stick magnitude (see RUN_STICK_ON/OFF).
var stick_running := false

var _orbit_ease := 0.0
var _cam_arm_k := 1.0
var _cam_arm_want := 1.0
var _cam_slide := 0.0
var _cam_slide_want := 0.0
var refl: WaterReflection
var refl_level := 0
var refl_auto := true
var fps_t := 0.0
var fps_n := 0
var fps_avg := 0.0
var fps_low := 0
var lbl_fps: Label
var url_opts := {}
var foliage: FoliageOcclusion
var _view_delta := 0.016

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
var joy: InputJoystick
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

const _GameUIScript = preload("res://game_ui.gd")
const _ThrowSessionScript = preload("res://throw_session.gd")
const _RestPoseScript = preload("res://rest_pose.gd")
const _DemoSequenceScript = preload("res://demo_sequence.gd")
var game_ui
var throw_session
var rest_pose
var demo_seq

func _ready() -> void:
	rng.seed = 99
	# After boy (priority 10): move then camera so follow uses the same-frame pose.
	process_priority = 20
	is_web = OS.has_feature("web")
	RenderingServer.set_default_clear_color(Color(0.02, 0.05, 0.08))
	ui_font = load("res://fonts/ui.otf")
	# CJK primary + Latin/Greek companion so HUD symbols (Δ etc.) never tofu —
	# Godot's shaper often skips Greek codepoints inside Noto CJK alone.
	var latin: Font = load("res://fonts/ui_latin.otf")
	if ui_font and latin and ui_font is FontFile:
		(ui_font as FontFile).fallbacks = [latin]
	_load_best()
	_build_environment()
	island = Island.new()
	add_child(island)
	island.build(ui_font)
	ground_sys = Ground.new()
	# Island collision must exist before the boy is placed, or spawn Y stays 0
	# and the first second of a drag eases him up out of the beach.
	ground_sys.setup(island, null)
	player_ctrl = PlayerController.new()
	player_ctrl.setup(ground_sys, self)
	follow_cam = FollowCamera.new()
	follow_cam.setup(self)
	game_ui = _GameUIScript.new()
	game_ui.bind(self)
	throw_session = _ThrowSessionScript.new()
	throw_session.bind(self)
	rest_pose = _RestPoseScript.new()
	rest_pose.bind(self)
	demo_seq = _DemoSequenceScript.new()
	demo_seq.bind(self)
	foliage = FoliageOcclusion.new()
	night_fx = NightFx.new()
	add_child(night_fx)
	night_fx.build(island)
	_build_player()
	ground_sys.setup(island, boy)
	if boy.has_method("bind_ground"):
		boy.bind_ground(ground_sys)
	if boy.foot_ik != null:
		boy.foot_ik.proof = _opt("poseproof")
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
	print_side.resize(PRINTS)
	for i in PRINTS:
		print_buf[i] = Vector4(0, 0, 0, -1000.0)
		print_wash[i] = -1.0
		print_side[i] = 0.0
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
	_sync_body_pose(true)
	if is_web and _opt("at") != "":
		_hat_probe_place.call_deferred(_opt("at"))
	if is_web and _opt("hatprobe") == "1":
		RenderingServer.frame_pre_draw.connect(_hat_probe_tick)
	if demo_mode:
		_start_audio()
		if "--selftest" in args:
			selftest = load("res://dev/selftest.gd").new()
			selftest.run.call_deferred(self)
		else:
			_run_demo4.call_deferred()
	if _opt("debug") == "1":
		dbg = preload("res://debug_hud.gd").new()
		add_child(dbg)
		dbg.setup(ui_font)
	_apply_camera()
	_update_ui()


func _sync_body_pose(hard := false) -> void:
	_body_pos = player.position
	_body_yaw = face_yaw
	if hard or not _body_sync:
		_body_pos_prev = _body_pos
		_body_yaw_prev = _body_yaw
		_body_sync = true


func _interp_body_pose() -> void:
	if player_ctrl != null:
		player_ctrl.present()
		return
	_sync_body_pose(true)

func _begin_cam_blend() -> void:
	follow_cam._begin_cam_blend()

func _is_ios_web() -> bool:
	if not is_web:
		return false
	var ua := str(JavaScriptBridge.eval("navigator.userAgent||''", true)).to_lower()
	return "iphone" in ua or "ipad" in ua or "ipod" in ua or "crios" in ua

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
	player_ctrl.write_position(sp)
	face_yaw = -0.35
	player_ctrl.write_yaw(face_yaw)
	ground_y = sp.y
	# Default view: 3/4-front so the Tripo face is readable (drag still orbits 360°)
	ex_yaw = face_yaw + PI + 0.45
	# Higher default pitch: low follow looking *up* a grass slope hid the legs
	# behind the hillside (gnd 0 cm but shorts-level silhouette). ~0.66 clears soles.
	# Slightly lower pitch + enough arm so head/hat stay inside the top margin
	# on tall phones (v35 CDP cropped the brim after stick release).
	ex_pitch = 0.46
	ex_dist = 4.0
	boy.ground_fn = _surface
	boy.ground_ray = func(from: Vector3, to: Vector3) -> Dictionary:
		return island.ray_ground(from, to, [boy.get_rid()] if boy else [])
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
		# phones: orthogonal + soft blur (2-splits doubled shadow primitives on WebGL2)
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 26.0
		sun.shadow_blur = 4.5
		sun.shadow_bias = 0.035
		sun.shadow_normal_bias = 1.4
		sun.directional_shadow_pancake_size = 3.0
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
	stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	return game_ui._label(size, col)


func _btn(text: String, size: int, primary := false) -> Button:
	return game_ui._btn(text, size, primary)


func _build_ui() -> void:
	return game_ui._build_ui()


func _angle_slider(t: String, k: String, lo: float, hi: float, v: float, band: Vector2) -> AngleSlider:
	return game_ui._angle_slider(t, k, lo, hi, v, band)


func _tall() -> bool:
	return game_ui._tall()

var safe := Vector4.ZERO
var safe_css := ""
var safe_t := 0.0

func _read_safe_area() -> bool:
	return game_ui._read_safe_area()

func _fit_action() -> void:
	return game_ui._fit_action()

func _layout_ui() -> void:
	return game_ui._layout_ui()


func _toast(t: String, dur := 1.4) -> void:
	return game_ui._toast(t, dur)


func _update_ui() -> void:
	return game_ui._update_ui()


func _toggle_view() -> void:
	if mode == Mode.VIEW:
		_begin_cam_blend()
		mode = Mode.EXPLORE if view_from == Mode.EXPLORE else Mode.THROW
		touches.clear()
		_update_ui()
		return
	if state != State.READY or not (mode == Mode.EXPLORE or mode == Mode.THROW):
		return
	view_from = mode
	touches.clear()
	orbit_vel = Vector2.ZERO
	_begin_cam_blend()
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
	return throw_session._enter_throw()


func _throw_walk_tick(delta: float) -> void:
	return throw_session._throw_walk_tick(delta)


func _leave_throw() -> void:
	return throw_session._leave_throw()


func _on_dock(x: float, z: float) -> bool:
	return (absf(x) < 1.15 and z < island.dock_start_z + 0.1 and z > island.dock_end_z + 3.6) or (absf(x) < 3.1 and z <= island.dock_end_z + 3.95 and z > island.dock_end_z - 0.12)

## Walkable surface height — single owner: Ground (render-mesh collision only).
func _surface(x: float, z: float) -> float:
	var hint: float = player.position.y if player else 5.0
	if player_ctrl != null:
		return player_ctrl.height(x, z, hint)
	if ground_sys != null:
		return ground_sys.height(x, z, hint)
	var ex: Array = []
	if player:
		ex.append(player.get_rid())
	return island.collision_h_walk(x, z, hint, ex)

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
	# Never step past the pier tip into open water (ray would miss deck boxes).
	if absf(x) < 5.0 and z < island.dock_end_z - 0.15:
		return false
	# Lip ramp is continuous — only reject real cliffs / reef jumps.
	if absf(h - from_h) > 0.55:
		return false
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
	if joy == null:
		return Vector2.ZERO
	return joy.read_move(demo_mode, demo_input)

func _explore_tick(delta: float) -> void:
	if player_ctrl != null:
		player_ctrl.physics_step(delta)

func _on_footstep(side: int, running: bool) -> void:
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
	# Cheap sand/dust puff under the planted sole (skip water / dock wood).
	if kind in ["sand", "grass"]:
		_dust_puff(side, running, kind)

# ------------------------------------------------------------------ rest: hammock nap / sunbathing

func _ensure_rest_align() -> void:
	return rest_pose._ensure_rest_align()



func _begin_rest(kind: String) -> void:
	return rest_pose._begin_rest(kind)



func _setup_seat_clip_rest(st: Dictionary) -> void:
	return rest_pose._setup_seat_clip_rest(st)



func _setup_hammock_clip_rest() -> void:
	return rest_pose._setup_hammock_clip_rest()



func hammock_prop_side() -> void:
	return rest_pose.hammock_prop_side()


const LIE_BACK := 0.085   # pelvis centre above the seat when lying on the back
const SEAT_LIE_DUR := 1.6
const LIE_BLEND_DUR := 0.6  # sun / hammock sit→lie blend
## Body half-length used to place hips/head/feet on lounger & hammock (Tripo ~0.8 m tall).
const LIE_BODY_HALF := 0.38
const LIE_CONTACT_TOL := 0.02  # 0–2 cm gap target after snap


## Hammock nap: hips at the sag centre, head/feet slightly raised; body follows the fabric curve.
func _setup_hammock_rest() -> void:
	return rest_pose._setup_hammock_rest()

func _hammock_stand_clear(bed: Vector3, side: Vector3, min_clear := 0.6) -> Vector3:
	return rest_pose._hammock_stand_clear(bed, side, min_clear)



func _nearest_trunk_dist(p: Vector3) -> float:
	return rest_pose._nearest_trunk_dist(p)



func _nearest_trunk_away(p: Vector3) -> Vector3:
	return rest_pose._nearest_trunk_away(p)

func _setup_lounger_rest() -> void:
	return rest_pose._setup_lounger_rest()

func _lie_down() -> void:
	return rest_pose._lie_down()


func _act_kind() -> String:
	return rest_pose._act_kind()

func _lie_basis(head_dir: Vector3) -> Basis:
	return rest_pose._lie_basis(head_dir)

func _lie_basis_oriented(head_dir: Vector3, into_bed: Vector3) -> Basis:
	return rest_pose._lie_basis_oriented(head_dir, into_bed)

func _lie_into_bed() -> Vector3:
	return rest_pose._lie_into_bed()

func _lie_swing() -> Transform3D:
	return rest_pose._lie_swing()

func _snap_sit_contact() -> void:
	return rest_pose._snap_sit_contact()

func _snap_hammock_sit_contact() -> void:
	return rest_pose._snap_hammock_sit_contact()

func _snap_lie_contact() -> void:
	return rest_pose._snap_lie_contact()



func _signed_gap(point: Vector3, surface: Vector3, normal: Vector3) -> float:
	return rest_pose._signed_gap(point, surface, normal)

func lie_contact_gaps() -> Dictionary:
	return rest_pose.lie_contact_gaps()

func _mesh_gap_near(bone_pos: Vector3, surface: Vector3, normal: Vector3, radius: float) -> float:
	return rest_pose._mesh_gap_near(bone_pos, surface, normal, radius)

func _plant_lie_feet() -> void:
	return rest_pose._plant_lie_feet()

func lie_penetration_depth() -> float:
	return rest_pose.lie_penetration_depth()

func lie_backrest_penetration_depth() -> float:
	return rest_pose.lie_backrest_penetration_depth()



func lounger_back_slab_clear() -> float:
	return rest_pose.lounger_back_slab_clear()

func lie_seat_penetration_depth() -> float:
	return rest_pose.lie_seat_penetration_depth()

func lie_mesh_penetration_depth(include_hat := true) -> float:
	return rest_pose.lie_mesh_penetration_depth(include_hat)


func _wake() -> void:
	return rest_pose._wake()



func _clip_name(phase: String) -> String:
	return rest_pose._clip_name(phase)



func _apply_boy_prop_root(clip_key: String) -> void:
	return rest_pose._apply_boy_prop_root(clip_key)



func _play_rest_enter_clip() -> void:
	return rest_pose._play_rest_enter_clip()



func _play_rest_idle_clip() -> void:
	return rest_pose._play_rest_idle_clip()



func _play_rest_exit_clip() -> void:
	return rest_pose._play_rest_exit_clip()



func _finish_rest_exit() -> void:
	return rest_pose._finish_rest_exit()



func _sync_hammock_cloth_to_boy() -> void:
	return rest_pose._sync_hammock_cloth_to_boy()



func _rest_tick_clips(delta: float) -> void:
	return rest_pose._rest_tick_clips(delta)



func _rest_tick(delta: float) -> void:
	return rest_pose._rest_tick(delta)


func _idle_hammock(delta: float) -> void:
	return rest_pose._idle_hammock(delta)

func _update_hammock_load() -> void:
	return rest_pose._update_hammock_load()


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

func _is_joy_finger(idx: int) -> bool:
	return joy != null and joy.touch_id != -2 and idx == joy.touch_id


func _touch_on_joystick(screen_pos: Vector2) -> bool:
	if joy == null or not joy.visible:
		return false
	var r := joy.get_global_rect()
	# Pad the hit area slightly — thumb often lands on the rim.
	r = r.grow(12.0)
	return r.has_point(screen_pos)


func _explore_cam_input(event: InputEvent) -> void:
	follow_cam._explore_cam_input(event)

func _explore_orbit(rel: Vector2) -> void:
	follow_cam._explore_orbit(rel)

func _flush_orbit_pending() -> void:
	follow_cam._flush_orbit_pending()

func _rest_cam_input(event: InputEvent) -> void:
	follow_cam._rest_cam_input(event)

func _view_input(event: InputEvent) -> void:
	follow_cam._view_input(event)

func _orbit_by(rel: Vector2) -> void:
	follow_cam._orbit_by(rel)

func _throw_input(event: InputEvent) -> void:
	return throw_session._throw_input(event)

func _throw_keys(delta: float) -> void:
	return throw_session._throw_keys(delta)


func _set_angles(el: float, tilt: float) -> void:
	return throw_session._set_angles(el, tilt)

func _begin_aim(p: Vector2, src := "script") -> void:
	return throw_session._begin_aim(p, src)


func _swipe_unit() -> float:
	return throw_session._swipe_unit()


func _swipe_press(p: Vector2, t: float) -> void:
	return throw_session._swipe_press(p, t)


func _swipe_move(p: Vector2, t: float) -> void:
	return throw_session._swipe_move(p, t)


func _swipe_release(p: Vector2, t: float) -> void:
	return throw_session._swipe_release(p, t)

func _apply_swipe(d: Vector2) -> void:
	return throw_session._apply_swipe(d)

func _swipe_yaw(d: Vector2) -> float:
	return throw_session._swipe_yaw(d)

func _flick(hist: Array) -> Array:
	return throw_session._flick(hist)


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
	return throw_session._aim_dir()

func _hand_pos() -> Vector3:
	return throw_session._hand_pos()

func _ideal_hand(yaw: float) -> Vector3:
	return throw_session._ideal_hand(yaw)


func _initial_velocity() -> Vector3:
	return throw_session._initial_velocity()


func _throw() -> void:
	return throw_session._throw()


func _hide_preview() -> void:
	return throw_session._hide_preview()


func _launch() -> void:
	return throw_session._launch()


func _hdist(p: Vector3) -> float:
	return throw_session._hdist(p)


func _hit_test(p: Vector3) -> String:
	return throw_session._hit_test(p)


func _step_stone(dt: float) -> void:
	return throw_session._step_stone(dt)

func _orient_stone(dt: float) -> void:
	return throw_session._orient_stone(dt)

func _judge(why: String, ang: float) -> void:
	return throw_session._judge(why, ang)


func _finish() -> void:
	return throw_session._finish()


func _stamp_footprint(side: int) -> void:
	# Phase-driven plant under the stance foot; skinned heel/ball refine yaw + placement.
	var yaw := face_yaw
	var side_sign := -1.0 if side == 0 else 1.0
	var right := Vector2(cos(yaw), -sin(yaw))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	# Kid sandal sits slightly outside the pelvis midline.
	var c := Vector2(player.global_position.x, player.global_position.z) \
		+ right * (0.065 * side_sign) + fwd * 0.02
	var fp := boy.foot_points(side)
	var heel: Vector3 = fp[0]
	var ball: Vector3 = fp[1]
	var f := Vector2(ball.x - heel.x, ball.z - heel.z)
	if f.length() >= 0.025:
		var skin_c := Vector2(heel.x, heel.z) + f * 0.55
		c = c.lerp(skin_c, 0.7)
		yaw = atan2(f.y, f.x)
	# only on dry or wet sand: not on the dock, the grass, in the sea or under the running wash
	if _surface_kind(c.x, c.y) != "sand" or Island.wash_covers(c.x, c.y, gt, 0.012):
		return
	print_buf[print_i] = Vector4(c.x, c.y, yaw, gt)
	print_wash[print_i] = -1.0
	print_side[print_i] = float(side)
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
	island.terrain_mat.set_shader_parameter("print_side", print_side)
	island.terrain_mat.set_shader_parameter("print_box", box)

## Night: at most 2–3 OmniLights near the player (campfire + nearest lamps/torches).
## Day: every Omni stays off (Compatibility forward multi-pass).
func _cap_night_omnis() -> void:
	if island == null or camera == null:
		return
	var cam_p := camera.global_position
	var night := night_k > 0.08
	# Torches: off by day; at night only the single nearest within range.
	var best_torch: Node = null
	var best_td := 1e9
	for tn in island.torches:
		if tn == null or tn.light == null:
			continue
		tn.light.visible = false
		tn.light.light_energy = 0.0
		if not night:
			continue
		var d: float = tn.global_position.distance_to(cam_p)
		if d < best_td and d < tn.light.omni_range + 8.0:
			best_td = d
			best_torch = tn
	if best_torch:
		best_torch.light.visible = true
		# energy already set in Torch._process from night; re-enable only.
		best_torch.light.light_energy = maxf(best_torch.light.light_energy, 0.35)
	# Campfire Omni: on at night only when the player is near the ring.
	if island.campfire and island.campfire.light:
		var fd: float = island.campfire.global_position.distance_to(cam_p)
		if (not night) or fd > 14.0:
			island.campfire.light.visible = false
			island.campfire.light.light_energy = 0.0
			island.campfire.light.shadow_enabled = false


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

## Soft ground AO under each sole — pairs with the mul-blend blob discs.
## Call AFTER late foot plant so XZ matches the rendered skinned soles.
## Only plant stance / near-contact feet — a swing-foot XZ painted a dark oval
## a shoe-length behind the lead foot (read as floating).
func _upload_foot_ao() -> void:
	if island == null or island.terrain_mat == null or boy == null or boy.skel == null:
		return
	if mode == Mode.REST:
		island.terrain_mat.set_shader_parameter("foot_ao", 0.0)
		return
	var pts: Array[Vector2] = []
	for side in range(2):
		var fp: Array = boy.foot_points(side)
		var heel: Vector3 = fp[0]
		var ball: Vector3 = fp[1]
		var mid: Vector3 = heel.lerp(ball, 0.55)
		var fgy := _surface(mid.x, mid.z)
		var sole_y := minf(heel.y - boy.sole_offset, ball.y - 0.012)
		var planted := boy._stance_locked[side] or (sole_y - fgy) < 0.03
		if planted:
			pts.append(Vector2(mid.x, mid.z))
	# Terrain foot-AO off: pier sand ghost ovals + rear-stance trail. Contact
	# discs (MeshInstance3D under each stance sole) own the grounding read.
	island.terrain_mat.set_shader_parameter("foot_ao", 0.0)
	if pts.is_empty():
		return
	island.terrain_mat.set_shader_parameter("foot_a_xz", pts[0])
	island.terrain_mat.set_shader_parameter("foot_b_xz", pts[1] if pts.size() > 1 else pts[0])


## Tiny sand / dust puff on footfall (CPUParticles — cheap, one-shot, auto-free).
func _dust_puff(side: int, running: bool, kind: String) -> void:
	var fp: Array = boy.foot_points(side)
	var mid: Vector3 = (fp[0] as Vector3).lerp(fp[1] as Vector3, 0.55)
	mid.y = _surface(mid.x, mid.z) + 0.02
	var dm := SphereMesh.new()
	dm.radius = 0.018
	dm.height = 0.036
	dm.radial_segments = 4
	dm.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.72, 0.62, 0.42, 1.0) if kind == "sand" else Color(0.45, 0.52, 0.32, 1.0)
	dm.material = mat
	var puff := CPUParticles3D.new()
	puff.mesh = dm
	puff.amount = 10 if running else 6
	puff.one_shot = true
	puff.explosiveness = 0.95
	puff.lifetime = 0.45 if running else 0.35
	puff.direction = Vector3(0, 1, 0)
	puff.spread = 55.0
	puff.initial_velocity_min = 0.35 if running else 0.2
	puff.initial_velocity_max = 0.9 if running else 0.55
	puff.gravity = Vector3(0, -2.5, 0)
	puff.damping_min = 1.5
	puff.damping_max = 3.0
	puff.scale_amount_min = 0.4
	puff.scale_amount_max = 1.1
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.05))
	puff.scale_amount_curve = curve
	puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	puff.emission_sphere_radius = 0.04
	add_child(puff)
	puff.global_position = mid
	puff.layers = 1 | WaterReflection.SKIP_LAYER
	puff.emitting = true
	get_tree().create_timer(1.2).timeout.connect(puff.queue_free)


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
		# AAA: don't park a banner over the boy for long — short tip, then clear.
		tip_timer = 4.5

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
	# Keep MobileQuality's softer PCF blur as a floor (was resetting to 2.5 and re-blocking path shadows).
	var base_blur: float = mq.shadow_blur if mq else 2.5
	sun.shadow_blur = lerpf(base_blur, maxf(base_blur, 5.0), k)
	sun.light_angular_distance = lerpf(1.2, 3.5, k)
	# Soft moon shadows — extra palm proxies must not crush path to pure black.
	sun.shadow_opacity = lerpf(1.0, 0.16, k)
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY if k > 0.55 else DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	# v26 night env — cool ambient; warmth = fire/lantern only (not ground albedo).
	env.ambient_light_color = Color(0.22, 0.30, 0.50).lerp(Color(0.45, 0.28, 0.18), sunset).lerp(Color(0.36, 0.40, 0.50), k)
	env.ambient_light_sky_contribution = lerpf(1.0, 0.26, k)
	env.ambient_light_energy = lerpf(0.55, 0.88, k)
	env.fog_light_color = Color(0.80, 0.86, 0.88).lerp(Color(0.95, 0.55, 0.30), sunset).lerp(Color(0.16, 0.20, 0.30), k)
	env.fog_density = lerpf(0.0045, 0.0024, k)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Exposure lift offsets 0.78 scale + shadow casters — keep cool, do not warm albedo.
	var expo_n := 1.18
	if mq and mq.mobile:
		expo_n = 1.22
	env.tonemap_exposure = lerpf(0.95, expo_n, k)
	env.tonemap_white = lerpf(3.2, 4.4, k)
	env.adjustment_saturation = lerpf(1.05, 0.96, k)
	env.adjustment_contrast = lerpf(1.02, 0.96, k)
	env.adjustment_brightness = lerpf(0.98, 1.06, k)
	var moon := sun.global_basis.z.normalized()
	island.water_mat.set_shader_parameter("glint_dir", moon)
	island.water_mat.set_shader_parameter("glint_col", Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.55, 0.28), sunset).lerp(Color(0.90, 0.93, 1.0), k))
	island.water_mat.set_shader_parameter("glint_gain", lerpf(1.0, 1.65, k))
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


## Project a world point to viewport UV (0..1). Behind camera → uv outside [0,1].
func _world_to_uv(world: Vector3) -> Vector2:
	if camera == null:
		return Vector2(-1, -1)
	if camera.is_position_behind(world):
		return Vector2(-1, -1)
	var screen: Vector2 = camera.unproject_position(world)
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		return Vector2(-1, -1)
	return Vector2(screen.x / vp.x, screen.y / vp.y)


## CDP reads window.__frame: head/feet UV + margins vs central 60% band.
func _export_frame_probe() -> void:
	if not is_web or boy == null or boy.skel == null or camera == null:
		return
	var head_w: Vector3 = player.global_position + Vector3(0, 1.25, 0)
	var foot_w := Vector3(player.global_position.x, player.global_position.y + 0.02, player.global_position.z)
	if boy.foot_ik != null and boy.foot_ik.pose_ready:
		head_w = boy.foot_ik.posed_head
		foot_w = boy.foot_ik.posed_feet
	var huv := _world_to_uv(head_w)
	var fuv := _world_to_uv(foot_w)
	# Central ~60% band (18–82% = 64% with tall-phone FOV tolerance).
	const LO := 0.18
	const HI := 0.82
	# Head sits upper-mid; feet lower-mid — both must stay inside the band.
	var head_ok := huv.x >= LO and huv.x <= HI and huv.y >= LO and huv.y <= HI
	var feet_ok := fuv.x >= LO and fuv.x <= HI and fuv.y >= LO and fuv.y <= HI
	var margin_min := 1e9
	for uv in [huv, fuv]:
		margin_min = minf(margin_min, uv.x - LO)
		margin_min = minf(margin_min, HI - uv.x)
		margin_min = minf(margin_min, uv.y - LO)
		margin_min = minf(margin_min, HI - uv.y)
	var g := {
		"head_uv": [huv.x, huv.y],
		"feet_uv": [fuv.x, fuv.y],
		"head_ok": head_ok,
		"feet_ok": feet_ok,
		"ok": head_ok and feet_ok,
		"margin_min": margin_min,
		"cam_step_cm": _cam_max_step_cm,
		"cam_orbit_step_cm": _cam_orbit_step_cm,
		"speed": cur_speed,
		"fixed": cam_fixed,
	}
	JavaScriptBridge.eval("window.__frame = " + JSON.stringify(g), true)


## HUD gnd = worst skinned-sole gap (burial preferred). Matches the picture.
func _refresh_gnd_hud_from_soles(min_gap: float, max_gap: float) -> void:
	# Negative gap = burial into terrain — that's what the player sees as sink.
	if min_gap < 0.0:
		dbg_gnd_err = absf(min_gap)
	else:
		dbg_gnd_err = absf(max_gap)
	if dbg:
		dbg.gnd_err = dbg_gnd_err
		dbg.max_step = dbg_max_step


## Measure both feet' drawable sole Y vs collision. Returns [min_gap, max_gap] metres.
func _skinned_sole_gaps() -> Array:
	if boy != null and boy.foot_ik != null:
		return boy.foot_ik.sole_gaps()
	var min_gap := 0.0
	var max_gap := 0.0
	var any := false
	if boy == null:
		return [0.0, 0.0]
	for side in range(2):
		var sy: float = boy.skinned_sole_y(side)
		var ax := player.global_position.x
		var az := player.global_position.z
		if boy._plant_ankle_xz.size() > side and boy._plant_ankle_xz[side].length_squared() > 1e-8:
			ax = boy._plant_ankle_xz[side].x
			az = boy._plant_ankle_xz[side].y
		var hy := _surface(ax, az)
		var gap := sy - hy
		if not any:
			min_gap = gap
			max_gap = gap
			any = true
		else:
			min_gap = minf(min_gap, gap)
			max_gap = maxf(max_gap, gap)
	return [min_gap, max_gap]


## CDP reads window.__ground: blob↔sole XZ and rendered sole gaps (post-IK frame).
func _export_ground_probe() -> void:
	if boy == null or boy.skel == null:
		return
	# Always refresh HUD from skinned soles (editor + web).
	var gaps: Array = _skinned_sole_gaps()
	var min_gap: float = float(gaps[0])
	var max_gap: float = float(gaps[1])
	_refresh_gnd_hud_from_soles(min_gap, max_gap)
	if not is_web:
		return
	# Disc centres vs each stance sole (max nearest-neighbour distance).
	# Discs are hidden while locomoting — blob_d stays 0 then (sun shadow only).
	var blob_d := 0.0
	var any_disc := false
	var mids: Array = boy.stance_sole_midpoints()
	for mid_v in mids:
		var mid: Vector3 = mid_v
		var best := 1e9
		for dnode in [boy.blob_l, boy.blob_r]:
			if dnode == null or not dnode.visible:
				continue
			any_disc = true
			var bp: Vector3 = dnode.global_position
			best = minf(best, Vector2(bp.x, bp.z).distance_to(Vector2(mid.x, mid.z)))
		if best < 1e8:
			blob_d = maxf(blob_d, best)
	var body_gnd := absf(player.global_position.y - _surface(player.global_position.x, player.global_position.z))
	var sole_l := min_gap
	var sole_r := max_gap
	var hit_l := 0.0
	var hit_r := 0.0
	var path := ""
	if boy.foot_ik != null:
		sole_l = boy.foot_ik.mesh_sole_y[0]
		sole_r = boy.foot_ik.mesh_sole_y[1]
		hit_l = boy.foot_ik.mesh_hit_y[0]
		hit_r = boy.foot_ik.mesh_hit_y[1]
		path = boy.foot_ik.pose_path
	var g := {
		"blob_d_cm": blob_d * 100.0,
		"sole_gap_cm": maxf(absf(min_gap), absf(max_gap)) * 100.0,
		"sole_gap_min_cm": min_gap * 100.0,
		"sole_gap_max_cm": max_gap * 100.0,
		"skin_gap_cm": (min_gap if min_gap < 0.0 else max_gap) * 100.0,
		"body_gnd_cm": body_gnd * 100.0,
		"pelvis_step_cm": player_ctrl.pelvis_step_m * 100.0 if player_ctrl != null else 0.0,
		"sole_y_l": sole_l,
		"sole_y_r": sole_r,
		"hit_l": hit_l,
		"hit_r": hit_r,
		"pose_path": path,
		"sole_off_cm": boy.sole_offset * 100.0,
		"disc_on": any_disc,
		"moving": boy.anim == "move" and boy.move_w > 0.2,
		"speed": cur_speed,
		"yaw": ex_yaw,
		"face": face_yaw,
		"pos": [player.global_position.x, player.global_position.y, player.global_position.z],
	}
	JavaScriptBridge.eval("window.__ground = " + JSON.stringify(g), true)


## &at=dock|hammock|towel|bench|slope: start next to it, so the browser check can rest there with the real buttons
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
		"slope":
			# Forest-grass burial spot used by CDP grounding checks.
			spots = [Vector3(2.6, 0, island.dock_start_z + 6.5)]
			want = ""
	for p: Vector3 in spots:
		_place(p, -0.4 if at == "slope" else 0.0)
		_update_action_kind()
		if want == "" or action_kind == want:
			break
	_snap_explore_cam()
	if at == "slope":
		# Force FOLLOW cam on the slope burial spot. A fixed/side-on lens let
		# him walk off-screen in CDP (empty grass + joystick only).
		cam_fixed = false
		set_meta("cdp_slope_cam", false)
		_persist_cam_fixed()
		ex_yaw = face_yaw
		ex_pitch = 0.46
		ex_dist = 4.0
		_snap_explore_cam(false)
		_cam_t_vel = Vector3.ZERO
		_cam_yaw_vel = 0.0
		_cam_pitch_vel = 0.0
		_cam_dist_vel = 0.0
		_cam_teleport = true
		_apply_camera(1.0)

## When > 0, timing/selftest scripts force this as the sim delta so soft-GL
## (slow frames) still advances at the requested fps instead of walking 10× farther.
var sim_dt_override := 0.0

func _process(delta: float) -> void:
	if dbg:
		dbg.begin_process()
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
	# Display pose = lerp between physics states (camera follows this).
	_interp_body_pose()
	# Next physics burst starts a new display interval from the current body.
	_body_new_frame = true
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
	# Throttle night omni / lamp pool / footprints (~15 Hz).
	_throttle_t += delta
	var do_heavy := _throttle_t >= 0.066
	if do_heavy:
		_throttle_t = 0.0
		night_fx.apply(night_k, camera.global_position, sun.global_basis.z.normalized(), 0.066)
		if mq and mq.omni_mul <= 0.0:
			_cap_night_omnis_off()
		else:
			_cap_night_omnis()
		_update_path_lamp_pool()
		_update_prints()
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
	# Explore walk is in _physics_process; rest/throw stay on render clock.
	match mode:
		Mode.REST:
			_rest_tick(delta)
			_sync_body_pose(true)
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
		_sync_body_pose(true)
	elif mode == Mode.THROW and (state == State.READY or state == State.AIMING or state == State.THROWING):
		_turn_to_aim(delta)
	else:
		boy.aim_twist = lerpf(boy.aim_twist, 0.0, 1.0 - exp(-delta * 8.0))
	_update_throw_pad()
	# Camera / foliage / probes run again from skeleton_updated, after FootIK
	# has written the pose the renderer is about to upload.
	_view_delta = delta
	if boy != null and boy.foot_ik != null and boy.foot_ik.proof == "override":
		_proof_override_foot()
	if boy == null or boy.skel == null or not boy.skel.skeleton_updated.is_connected(boy._on_skeleton_updated):
		_on_final_pose()
	_update_audio(delta)
	_audio_tick(delta)
	if mq:
		mq.watch_frame(delta, get_viewport(), sun, refl_level, _set_refl_level)
	if dbg:
		dbg.gnd_err = dbg_gnd_err
		dbg.max_step = dbg_max_step
		dbg.end_process()
		dbg.note_frame(delta, mq.scale_3d if mq else 1.0, mq.tier_name() if mq else "?")

func _physics_process(delta: float) -> void:
	if dbg:
		dbg.begin_physics()
	# Only latch prev on the first physics tick of this render frame. If we
	# overwrite prev every tick, a 2-step frame drops the first Δ and the boy
	# teleports by one physics step on hitch/ProMotion catch-up.
	if _body_new_frame:
		_body_pos_prev = _body_pos
		_body_yaw_prev = _body_yaw
		_body_new_frame = false
	if mode == Mode.EXPLORE:
		_explore_tick(delta)
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
	if dbg:
		dbg.end_physics()


func _cap_night_omnis_off() -> void:
	## &q=min: kill night omnis for GPU isolation.
	if island == null:
		return
	for tn in island.torches:
		if tn and tn.light:
			tn.light.visible = false
			tn.light.light_energy = 0.0
	if island.campfire and island.campfire.light:
		island.campfire.light.visible = false
		island.campfire.light.light_energy = 0.0
		island.campfire.light.shadow_enabled = false
	if night_fx:
		night_fx.apply(0.0, camera.global_position if camera else Vector3.ZERO, Vector3.FORWARD, 0.0)

## Throw-mode camera: right behind the stone in his hand, looking along the aim over his shoulder, so the
## aim line runs up the screen. While a finger is down it turns part way towards the aim, and all the way
## once the stone is thrown.
func _throw_cam() -> Array:
	return follow_cam._throw_cam()

func _turn_to_aim(delta: float) -> void:
	var r := player.rotation.y
	if state == State.READY:
		player_ctrl.write_yaw(lerp_angle(r, aim_yaw, 1.0 - exp(-delta * 10.0)))
		boy.aim_twist = lerpf(boy.aim_twist, 0.0, 1.0 - exp(-delta * 10.0))
		return
	r = lerp_angle(r, aim_yaw, 1.0 - exp(-delta * (26.0 if state == State.THROWING else 2.5)))
	var tw := wrapf(aim_yaw - r, -PI, PI)
	if absf(tw) > TWIST_MAX:
		r = aim_yaw - signf(tw) * TWIST_MAX
		tw = signf(tw) * TWIST_MAX
	player_ctrl.write_yaw(r)
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
	return follow_cam._explore_cam()

func _crit_damp(current: float, target: float, vel: float, smooth_time: float, dt: float) -> Array:
	return follow_cam._crit_damp(current, target, vel, smooth_time, dt)

func _crit_damp_vec3(current: Vector3, target: Vector3, vel: Vector3, smooth_time: float, dt: float) -> Array:
	return follow_cam._crit_damp_vec3(current, target, vel, smooth_time, dt)

func _crit_damp_angle(current: float, target: float, vel: float, smooth_time: float, dt: float) -> Array:
	return follow_cam._crit_damp_angle(current, target, vel, smooth_time, dt)

func _rest_bone(name: String, fallback: Vector3) -> Vector3:
	return follow_cam._rest_bone(name, fallback)

func _rest_cam_target() -> Vector3:
	return follow_cam._rest_cam_target()

func _rest_face_fwd() -> Vector3:
	return follow_cam._rest_face_fwd()

func _rest_frame_dist(fig_h: float) -> float:
	return follow_cam._rest_frame_dist(fig_h)

func _rest_cam() -> Array:
	return follow_cam._rest_cam()

func _pick_rest_framing(t: Vector3, head: Vector3, hips: Vector3, pitch: float, dist: float) -> Array:
	return follow_cam._pick_rest_framing(t, head, hips, pitch, dist)

func _score_rest_view(t: Vector3, head: Vector3, cam: Vector3, yaw: float, pitch: float, dist: float) -> float:
	return follow_cam._score_rest_view(t, head, cam, yaw, pitch, dist)

func _rest_los_blocked(cam: Vector3, head: Vector3) -> bool:
	return follow_cam._rest_los_blocked(cam, head)

func _rest_los_adjust(t: Vector3, head: Vector3, yaw: float, pitch: float, dist: float) -> Array:
	return follow_cam._rest_los_adjust(t, head, yaw, pitch, dist)

func _clear_yaw(t: Vector3, pref: float, pitch: float, dist: float) -> float:
	return follow_cam._clear_yaw(t, pref, pitch, dist)

func _seg_hits_trunk(a: Vector3, b: Vector3, pts: Array) -> bool:
	return follow_cam._seg_hits_trunk(a, b, pts)

func _snap_explore_cam(front := false) -> void:
	follow_cam._snap_explore_cam(front)

func _toggle_cam_fixed() -> void:
	follow_cam._toggle_cam_fixed()

func _nudge_zoom(factor: float) -> void:
	follow_cam._nudge_zoom(factor)

func _persist_cam_fixed() -> void:
	follow_cam._persist_cam_fixed()

func _load_cam_fixed() -> void:
	follow_cam._load_cam_fixed()

func _mix_cam_blend() -> void:
	follow_cam._mix_cam_blend()

func _apply_foliage_cutout() -> void:
	if foliage == null or island == null:
		return
	if demo_nocut:
		foliage.apply(island, camera.global_position if camera else Vector3.ZERO, Vector3(0, -100, 0), Vector3(0, -100, 0), 0.0, false)
		return
	var head := player.global_position + Vector3(0, 1.25, 0)
	var feet := player.global_position + Vector3(0, 0.04, 0)
	if boy != null and boy.foot_ik != null and boy.foot_ik.pose_ready:
		head = boy.foot_ik.posed_head
		feet = boy.foot_ik.posed_feet
	foliage.apply(island, camera.global_position if camera else Vector3.ZERO, head, feet, cur_speed, mode == Mode.EXPLORE)
	_cut_focus = foliage.focus


func _on_final_pose() -> void:
	## After FootIK, before the skeleton upload is restored. Camera, foliage
	## and the sole probe all read this same pose.
	_update_camera(_view_delta)
	_apply_foliage_cutout()
	if boy != null and boy.has_method("_update_blob"):
		boy._update_blob()
	_export_ground_probe()


func _proof_override_foot() -> void:
	## Comparison path: global-pose override only, modifier skipped.
	## A web screenshot of ?poseproof=override shows whether this channel draws.
	var skel := boy.skel
	if skel == null:
		return
	var fi := skel.find_bone("mixamorig_LeftFoot")
	if fi < 0:
		return
	var xf := skel.get_bone_global_pose(fi)
	xf.origin.y += 0.42
	skel.set_bone_global_pose_override(fi, xf, 1.0, true)


## Fallback if FollowCamera is missing — camera then cutout.
func _finalize_view() -> void:
	_on_final_pose()


func _update_camera(delta: float) -> void:
	follow_cam._update_camera(delta)

func _cam_blocked(q: Vector3) -> bool:
	return follow_cam._cam_blocked(q)

func _apply_camera(delta: float = 1.0 / 60.0) -> void:
	follow_cam._apply_camera(delta)

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
	# iOS/WebKit defaults to LOW; URL ?q=high|mid|low|min freezes the ladder.
	mq.setup(is_web, _opt("mobile") == "1", get_viewport(), sun, _is_ios_web())
	mq.changed.connect(func(_t: int) -> void: _apply_mq_materials())
	var q_opt := _opt("q", "")
	if q_opt != "":
		mq.force_tier(q_opt, get_viewport(), sun)
	_apply_mq_materials()
	var want := _opt("refl", "auto")
	refl_auto = want == "auto" and q_opt == ""
	# On phones start with reflection off; ?q=min forces shadows+refl off.
	var start_l := 2 if mq.mobile else 0
	if q_opt == "min" or not mq.shadows_on:
		start_l = 3
	_set_refl_level({"0": 2, "low": 1}.get(want, start_l))
	if _opt("shadow") == "0" or q_opt == "min":
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
		# cheap≥1 skips wave/boat glitter paths in water.gdshader (= "no water waves" for min).
		island.water_mat.set_shader_parameter("cheap", mq.water_cheap)
	if island and island.leaf_mat:
		island.leaf_mat.set_shader_parameter("near_fade", mq.leaf_near_fade * (2.0 if mq.foliage_mul < 0.75 else 1.0))
	_scale_particles(mq.particle_mul)
	if sun:
		sun.shadow_enabled = mq.shadows_on and refl_level < 3

func _scale_particles(mul: float) -> void:
	for n in get_tree().get_nodes_in_group("v27_particles") if get_tree() else []:
		if n is CPUParticles3D:
			var p := n as CPUParticles3D
			if not p.has_meta("base_amount"):
				p.set_meta("base_amount", p.amount)
			if mul <= 0.001:
				p.amount = 1
				p.emitting = false
			else:
				p.emitting = true
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
	return demo_seq._run_sim_report()

func _walk_metrics_report() -> void:
	return demo_seq._walk_metrics_report()


func _sim_block() -> void:
	return demo_seq._sim_block()

func sim_throw(pw: float, el: float, tilt: float, s: float, stance := "stand") -> Dictionary:
	return demo_seq.sim_throw(pw, el, tilt, s, stance)

func sim_sweeps() -> Array[String]:
	return demo_seq.sim_sweeps()


func _demo_shot(name: String) -> void:
	return demo_seq._demo_shot(name)


func _wait(sec: float) -> void:
	await demo_seq._wait(sec)


var walk_gen := 0

func _walk_to(target: Vector3, run: bool, timeout := 14.0) -> void:
	await demo_seq._walk_to(target, run, timeout)


func _hd(a: Vector3, b: Vector3) -> float:
	return demo_seq._hd(a, b)


func _stop_walk() -> void:
	return demo_seq._stop_walk()


func _place(p: Vector3, yaw: float) -> void:
	return demo_seq._place(p, yaw)


func _track(yaw_off: float, pitch: float, dist: float, h: float) -> void:
	return demo_seq._track(yaw_off, pitch, dist, h)


func _free_cam() -> void:
	return demo_seq._free_cam()


func _fixed_cam(target: Vector3, yaw: float, pitch: float, dist: float) -> void:
	return demo_seq._fixed_cam(target, yaw, pitch, dist)


func _shot(name: String) -> void:
	return demo_seq._shot(name)


func _throw_sequence(pre: String, crouch: bool, close: bool) -> void:
	await demo_seq._throw_sequence(pre, crouch, close)


func _rest_sequence(pre: String, kind: String, close: bool) -> void:
	await demo_seq._rest_sequence(pre, kind, close)

func _shore_sequence(pre: String) -> void:
	await demo_seq._shore_sequence(pre)

func _v8_sequence(pre: String) -> void:
	await demo_seq._v8_sequence(pre)

func _v9_sequence(pre: String, part: String) -> void:
	await demo_seq._v9_sequence(pre, part)

func _v11_sequence(pre: String, part: String) -> void:
	await demo_seq._v11_sequence(pre, part)

func _v12_sequence(pre: String, part: String) -> void:
	await demo_seq._v12_sequence(pre, part)

func _v14_sequence(pre: String) -> void:
	await demo_seq._v14_sequence(pre)

func _demo_swipe(from: Vector2, to: Vector2, sec: float, hold: float, flick: bool, shot := "") -> void:
	await demo_seq._demo_swipe(from, to, sec, hold, flick, shot)


func _demo_wait_ready(shots: Array) -> void:
	await demo_seq._demo_wait_ready(shots)

func _shoulder_pos(side := "r") -> Vector3:
	return demo_seq._shoulder_pos(side)

func _v16_sequence(pre: String) -> void:
	await demo_seq._v16_sequence(pre)

func _face_cam(yaw: float, pitch: float, dist: float) -> void:
	return demo_seq._face_cam(yaw, pitch, dist)


func _follow_head(dur: float, yaw: float, pitch: float, dist: float, yaw_end := INF) -> void:
	await demo_seq._follow_head(dur, yaw, pitch, dist, yaw_end)

func _bone_pos(bone: String, up := 0.0) -> Vector3:
	return demo_seq._bone_pos(bone, up)

func _v17_sequence(pre: String, part: String) -> void:
	await demo_seq._v17_sequence(pre, part)

func _v18_sequence(pre: String) -> void:
	await demo_seq._v18_sequence(pre)

func _v19_sequence(pre: String) -> void:
	await demo_seq._v19_sequence(pre)

func _v20_sequence(pre: String, part: String) -> void:
	await demo_seq._v20_sequence(pre, part)

func _v21_sequence(pre: String, ver := "v21", dk := 1.0) -> void:
	await demo_seq._v21_sequence(pre, ver, dk)

func _v15_sequence(pre: String) -> void:
	await demo_seq._v15_sequence(pre)

func _explore_sequence(pre: String) -> void:
	await demo_seq._explore_sequence(pre)


func _run_demo4() -> void:
	await demo_seq._run_demo4()


func _video_seg(seg: String) -> void:
	await demo_seq._video_seg(seg)

func _drive_dir(dir: Vector3, sec: float, run: bool) -> void:
	await demo_seq._drive_dir(dir, sec, run)

func _bump_spot(w: Array) -> Array:
	return demo_seq._bump_spot(w)

func _stick_walk(dirs: Array, sec_each: float) -> void:
	await demo_seq._stick_walk(dirs, sec_each)


func _snap_cam_now() -> void:
	return demo_seq._snap_cam_now()

