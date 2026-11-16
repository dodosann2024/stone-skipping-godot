extends Node
## Frame order:
## 1. Physics (60 Hz): stick → PlayerBody.move_and_slide on Ground. One root writer.
## 2. Render: AnimationPlayer → FootIK (skeleton space) → camera arm → occluder fade.
## Nothing else samples the ground to move the body.

var ground: Ground
var player: PlayerBody
var rig: CameraRig
var fader: OccluderFader
var joy: JoyStick
var hud: Hud
var dbg: DebugHud
var amb: Ambience
var props: Props
var live := false
var night := false
var sun: DirectionalLight3D
var water_mat: ShaderMaterial
var sky_mat: ProceduralSkyMaterial
var _orbit := -1
var _best_skips := 0
var _best_dist := 0.0
var _sitting := false
var _pose_ready := false
var _lying := false
var _sit_align := false
var _pose_msec := 0
var _audit_still := 0.0
var _audit_spot := Vector2.ZERO
var _crouch := false
var _throwing := false
var rest_kind := ""
var _rest_item: Fadable


func _ready() -> void:
	_world()
	_player()
	_camera()
	_ui()
	_audio()
	var q := _query()
	if q.contains("debug=1"):
		dbg.on = true
		dbg.visible = true
	if q.contains("occ=0"):
		fader.enabled = false
	if q.contains("shot=") or OS.get_environment("R42_ROUTE") == "1" or OS.get_environment("R42_SHOT") == "1" or DisplayServer.get_name() == "headless":
		_begin()
		if q.contains("shot="):
			_pose_shot()
	else:
		_start_gate()


func _world() -> void:
	var envn := WorldEnvironment.new()
	envn.name = "WorldEnvironment"
	var env := Environment.new()
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.68, 0.92)
	sky_mat.sky_horizon_color = Color(0.78, 0.88, 0.92)
	sky_mat.ground_horizon_color = Color(0.55, 0.72, 0.7)
	sky_mat.ground_bottom_color = Color(0.16, 0.28, 0.32)
	sky_mat.sun_angle_max = 14.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.74)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	envn.environment = env
	add_child(envn)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, 48, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.shadow_blur = 0.8
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 14.0
	add_child(sun)
	ground = Ground.new()
	add_child(ground)
	var gmat := _ground_mat()
	if gmat != null:
		gmat.set_shader_parameter("cheap", 0.0)
	props = Props.new()
	add_child(props)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 90)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	water.mesh = plane
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/sea.gdshader")
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The web build is what the phone runs. The lace path stays in the shader behind cheap=0.
	water_mat.set_shader_parameter("cheap", 0.0)
	water.position.y = 0.02
	add_child(water)


func _player() -> void:
	player = PlayerBody.new()
	var ends := IslandData.dock_ends()
	player.position = Vector3(0.0, Constants.DECK_Y + 0.05, ends.y + 1.3)
	player.face_yaw = PI
	player.rotation.y = PI
	player.cam_basis = Basis(Vector3.UP, PI)
	add_child(player)
	player.ground = ground
	await get_tree().process_frame
	if player.boy != null:
		player.boy.bind_ground(ground)
	player.stepped.connect(_on_step)
	if player.boy != null and player.boy.arm != null:
		player.boy.arm.released.connect(_on_release)
		player.boy.arm.finished.connect(_on_throw_done)
	_load_save()


func _camera() -> void:
	rig = CameraRig.new()
	rig.player = player
	rig.yaw = player.face_yaw
	add_child(rig)
	fader = OccluderFader.new()
	fader.camera = rig.cam
	fader.player = player
	fader.props = props
	add_child(fader)


func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.action.connect(_on_action)
	dbg = DebugHud.new()
	layer.add_child(dbg)
	joy = JoyStick.new()
	layer.add_child(joy)


func _audio() -> void:
	amb = Ambience.new()
	add_child(amb)


func _start_gate() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Start"
	layer.layer = 10
	add_child(layer)
	var b := Button.new()
	b.text = "点击开始"
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	var font := load("res://assets/ui.otf") as Font
	if font != null:
		b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 28)
	layer.add_child(b)
	b.pressed.connect(func() -> void:
		layer.queue_free()
		_begin()
	)


func _begin() -> void:
	live = true
	amb.start()
	if OS.has_feature("web") and hud != null and hud.sound_tip != null:
		hud.sound_tip.visible = true
	if dbg != null and dbg.on:
		var ends := IslandData.dock_ends()
		var bench := _seat_named("Bench")
		if bench != null:
			print("MARK bench %.2f %.2f" % [bench.global_position.x, bench.global_position.z])
		print("MARK tee %.2f %.2f" % [0.15, ends.y + 2.4])


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var nk := 1.0 if night else 0.0
	if water_mat != null:
		water_mat.set_shader_parameter("game_time", t)
		water_mat.set_shader_parameter("night_k", nk)
		_push_ripples(t)
	var gmat := _ground_mat()
	if gmat != null:
		gmat.set_shader_parameter("game_time", t)
		gmat.set_shader_parameter("night_k", nk)
	if not live:
		return
	player.stick = joy.value
	var auto := _audit_stick()
	if auto.length() > 0.02:
		var spot := Vector2(player.global_position.x, player.global_position.z)
		if spot.distance_to(_audit_spot) < 0.1:
			_audit_still += delta
		else:
			_audit_spot = spot
			_audit_still = 0.0
		# A trunk in the wish direction stalls the walk. Step sideways until it clears.
		# Sidestep only on the island. On the pier a sideways shove walks off the
		# planks and the lip snap puts him back, so he never reaches the tee.
		if _audit_still > 0.45 and player.global_position.z > IslandData.dock_ends().x + 2.0:
			var side := 1.0 if int(_audit_still / 0.55) % 2 == 0 else -1.0
			auto = Vector2(side, -0.35).limit_length(1.0)
		player.stick = auto
	else:
		_audit_still = 0.0
	if hud != null and hud.sound_tip != null and hud.sound_tip.visible and joy.value.length() > 0.2:
		hud.sound_tip.visible = false
	_prompts()
	if dbg != null:
		dbg.note(delta, player.speed > 0.12)
		if dbg.on and Engine.get_process_frames() % 8 == 0:
			var fwd := -player.cam_basis.z
			fwd.y = 0.0
			if fwd.length_squared() < 1e-8:
				fwd = Vector3(0, 0, 1)
			else:
				fwd = fwd.normalized()
			print("NAV %.2f %.2f %.3f %.3f stick %.2f %.2f" % [player.global_position.x, player.global_position.z, fwd.x, fwd.z, player.stick.x, player.stick.y])
	if _sit_align and not _lying:
		_plant_on_seat(_sit_weight())
	if dbg != null and dbg.on and Engine.get_process_frames() % 45 == 0:
		_fade_audit()


func _unhandled_input(event: InputEvent) -> void:
	if not live or _sitting:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if joy.take(touch):
			player.stick = joy.value
			return
		if touch.pressed:
			_orbit = touch.index
		elif touch.index == _orbit:
			_orbit = -1
			rig.looking = false
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if joy.drag(drag):
			player.stick = joy.value
			return
		if drag.index == _orbit:
			rig.note_drag()
			rig.yaw -= drag.relative.x * 0.006
			var pitch_add := drag.relative.y * 0.004
			rig.pitch = clampf(rig.pitch + pitch_add, deg_to_rad(30.0), deg_to_rad(40.0))
	elif event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_W:
			joy.value = Vector2(0, -1)
		elif k.keycode == KEY_S:
			joy.value = Vector2(0, 1)


func _audit_stick() -> Vector2:
	# The touch harness sets window.__gx/__gz. The same camera-relative stick
	# the route uses then walks there every physics frame. A finger still wins
	# once the page clears the goal.
	if not Engine.has_singleton("JavaScriptBridge"):
		return Vector2.ZERO
	var js: Object = Engine.get_singleton("JavaScriptBridge")
	var raw = js.call("eval", "(window.__gx==null?'':(''+window.__gx+','+window.__gz))", true)
	var s := str(raw)
	if s == "" or not s.contains(","):
		return Vector2.ZERO
	var parts := s.split(",")
	if parts.size() < 2:
		return Vector2.ZERO
	var goal := Vector2(float(parts[0]), float(parts[1]))
	var here := Vector2(player.global_position.x, player.global_position.z)
	var dir := goal - here
	if dir.length() < 0.35:
		return Vector2.ZERO
	dir = dir.normalized()
	var fwd := -player.cam_basis.z
	fwd.y = 0.0
	fwd = Vector3(0, 0, 1) if fwd.length_squared() < 1e-6 else fwd.normalized()
	var right := player.cam_basis.x
	right.y = 0.0
	right = right.normalized()
	var world := Vector3(dir.x, 0.0, dir.y)
	return Vector2(world.dot(right), -world.dot(fwd)).limit_length(1.0)


func _prompts() -> void:
	var p := player.global_position
	var ends := IslandData.dock_ends()
	var on_tee := absf(p.x) < 3.2 and p.z < ends.y + 4.2 and p.z > ends.y - 1.0
	var busy := _sitting or _throwing
	# Stay on screen through the throw. v43 kept 打水漂 and 半蹲 up while the stone flew.
	hud.throw_btn.visible = on_tee and not _sitting
	hud.pose_btn.visible = on_tee and not _sitting
	hud.pose_btn.text = "站立" if _crouch else "半蹲"
	var near := _nearest_seat()
	var kind := ""
	if near != null:
		kind = str(near.get_meta("kind", ""))
	var can_sit := kind == "bench" or kind == "log"
	var can_sleep := kind == "hammock"
	var can_sun := kind == "towel" or kind == "lounger"
	hud.sit_btn.visible = not busy and (can_sit or can_sleep or can_sun)
	if can_sleep:
		hud.sit_btn.text = "睡觉"
	elif can_sun:
		hud.sit_btn.text = "晒太阳"
	else:
		hud.sit_btn.text = "坐下"
	var seated := rest_kind == "bench" or rest_kind == "log"
	# 躺下 and 起来 wait until the hips are actually on the seat.
	hud.lie_btn.visible = _pose_ready and seated and not _lying
	hud.up_btn.visible = (_pose_ready or _lying) and _sitting and not _throwing


func _on_action(name: String) -> void:
	if name == "夜晚" or name == "白天":
		night = not night
		_apply_night()
		_save()
	elif name == "声音：开" or name == "声音：关":
		amb.muted = not amb.muted
		hud.sound_btn.text = "声音：关" if amb.muted else "声音：开"
		if amb.muted:
			amb.ocean.stop()
		else:
			amb.start()
	elif name == "打水漂":
		_throw()
	elif name == "半蹲" or name == "站立":
		_crouch = not _crouch
	elif name == "观景":
		rig.hold_pitch = not rig.hold_pitch
	elif name == "固定视角":
		rig.follow = not rig.follow
	elif name == "帧时间":
		dbg.on = not dbg.on
		dbg.visible = dbg.on
		if dbg.copy_btn != null:
			dbg.copy_btn.visible = dbg.on
	elif name == "坐下" or name == "睡觉" or name == "晒太阳":
		var seat := _nearest_seat()
		if seat != null:
			_begin_rest(seat)
	elif name == "躺下":
		_begin_lie()
	elif name == "起来":
		_end_rest()


func _nearest_seat() -> Fadable:
	var best: Fadable
	var best_d := 1.7
	var p := player.global_position
	for item in props.items:
		if not item.has_meta("kind"):
			continue
		var d := item.global_position.distance_to(p)
		if d < best_d:
			best = item
			best_d = d
	return best


func _begin_rest(item: Fadable) -> void:
	if _sitting or player.boy == null:
		return
	_sitting = true
	_pose_ready = false
	_lying = false
	_sit_align = false
	_rest_item = item
	rest_kind = str(item.get_meta("kind", ""))
	item.hold_solid(true)
	joy.value = Vector2.ZERO
	player.stick = Vector2.ZERO
	player.locked = true
	var yaw := float(item.get_meta("yaw", 0.0))
	var pos := _seat_pos(item)
	if rest_kind == "bench":
		# Stand just in front of the seat, back toward the backrest, then sit down onto it.
		yaw = PI
		pos = item.global_transform * Vector3(0.0, 0.0, 0.78)
		pos.y = item.global_position.y + 0.02
		rig.framing = "seat"
		rig.pivot_y = 0.48
	else:
		rig.framing = "front"
		rig.pivot_y = 0.45 if rest_kind == "towel" or rest_kind == "lounger" or rest_kind == "hammock" else 0.7
	await _glide(pos, yaw, true)
	if rest_kind == "lounger" or rest_kind == "towel":
		player.boy.play_clip("lounger_lie", 0.2)
		return
	var enter := _clip_for(rest_kind, "enter")
	var idle := _clip_for(rest_kind, "idle")
	_sit_align = rest_kind == "bench"
	if enter != "":
		player.boy.play_clip(enter, 0.15)
		await _wait_clip(8.0 if rest_kind != "hammock" else 12.0)
	if idle != "":
		player.boy.play_clip(idle, 0.2)
	else:
		player.boy.play_clip("sit", 0.2)
	_plant_on_seat(1.0)


func _begin_lie() -> void:
	if player.boy == null:
		return
	if player.boy.rest != null:
		player.boy.rest.mode = ""
	if rest_kind == "bench" and _rest_item != null:
		_lying = true
		_sit_align = false
		_apply_bench_lie(_rest_item)
		await get_tree().process_frame
		_snap_bench(_rest_item.global_position)
		rig.framing = "lie"
		rig.pivot_y = 0.35
		return
	var clip := "lounger_lie" if rest_kind == "lounger" else "bench_lie"
	player.boy.play_clip(clip, 0.2)
	rig.pivot_y = 0.55


func _end_rest() -> void:
	if not _sitting:
		return
	var kind := rest_kind
	if player.boy != null and player.boy.rest != null:
		player.boy.rest.mode = ""
	if kind == "bench" or kind == "log" or kind == "hammock":
		var exit_name := _clip_for(kind, "exit")
		if exit_name != "" and player.boy != null:
			player.boy.play_clip(exit_name, 0.15)
			await _wait_clip(8.0 if kind != "hammock" else 12.0)
	var back := player.global_position
	var yaw := player.face_yaw
	var step := Vector3(-sin(yaw), 0, -cos(yaw)) * -0.55
	await _glide(back + step, yaw, true)
	if player.boy != null:
		player.boy.clear_hold()
	if _rest_item != null:
		_rest_item.hold_solid(false)
	_sitting = false
	_pose_ready = false
	_lying = false
	_sit_align = false
	rest_kind = ""
	_rest_item = null
	player.locked = false
	player.use_anchor = false
	rig.framing = ""
	rig.tight = false
	rig.pivot_y = 0.62


func _sit_weight() -> float:
	if player.boy == null or player.boy.anim == null:
		return 1.0
	var anim := player.boy.anim
	var cur := str(anim.current_animation)
	if cur.ends_with("bench_sit_idle") or cur.ends_with("/sit") or cur == "sit":
		return 1.0
	if not cur.contains("enter"):
		return 0.85
	var clip := anim.get_animation(anim.current_animation)
	if clip == null or clip.length < 0.1:
		return 1.0
	return clampf((anim.current_animation_position / clip.length - 0.4) / 0.6, 0.0, 1.0)


func _plant_on_seat(weight: float) -> void:
	if weight < 0.02 or _rest_item == null or player.boy == null or player.boy.skel == null:
		return
	var skel: Skeleton3D = player.boy.skel
	var hi := skel.find_bone("mixamorig_Hips")
	if hi < 0:
		return
	skel.force_update_all_bone_transforms()
	var hip: Vector3 = (skel.global_transform * skel.get_bone_global_pose(hi)).origin
	# Slats are about 0.44 m above the bench origin, just in from the front edge.
	var seat: Vector3 = _rest_item.global_transform * Vector3(0.0, 0.46, 0.06)
	var delta := (seat - hip) * weight
	if delta.length() > 0.28:
		delta = delta.normalized() * 0.28
	player.global_position += delta
	player.anchor = player.global_position
	player.use_anchor = true
	player.face_yaw = PI
	player.rotation.y = PI
	var hip2: Vector3 = hip + delta
	var cur := ""
	if player.boy.anim != null:
		cur = str(player.boy.anim.current_animation)
	if cur.ends_with("bench_sit_idle") and not _pose_ready:
		_pose_ready = true
		_pose_msec = Time.get_ticks_msec()
		print("SIT_READY")
	if _pose_ready and rig != null:
		rig.tight = Time.get_ticks_msec() - _pose_msec > 1500


func _fade_audit() -> void:
	var bad: Array[String] = []
	if player.boy != null:
		_scan_fade(player.boy, "boy", bad, true)
	if _rest_item != null:
		_scan_fade(_rest_item, "seat", bad, true)
	if props != null:
		for i in props.lod_count():
			if props.lod_both_visible(i):
				bad.append("lod doubled")
		for item in props.items:
			_scan_prop_fade(item, bad)
	if bad.is_empty():
		return
	print("FADE_FAIL %s" % " ".join(bad))


func _scan_prop_fade(node: Node, bad: Array[String]) -> void:
	if str(node.name) == "Flame":
		return
	if node is MeshInstance3D:
		var mat := (node as MeshInstance3D).material_override as StandardMaterial3D
		if mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and mat.albedo_color.a < 0.99:
			bad.append("%s alpha-blend" % node.name)
	for c in node.get_children():
		_scan_prop_fade(c, bad)


func _scan_fade(node: Node, tag: String, bad: Array[String], must_solid: bool) -> void:
	if must_solid and node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		if gi.transparency > 0.01:
			bad.append("%s instance-fade %.2f" % [tag, gi.transparency])
			gi.transparency = 0.0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mats: Array[Material] = []
		if mi.material_override != null:
			mats.append(mi.material_override)
		for s in mi.get_surface_override_material_count():
			var sm := mi.get_surface_override_material(s)
			if sm != null:
				mats.append(sm)
		for mat in mats:
			var std := mat as StandardMaterial3D
			if std == null:
				continue
			if must_solid and (std.albedo_color.a < 0.99 or std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
				bad.append("%s alpha %.2f" % [tag, std.albedo_color.a])
				std.albedo_color.a = 1.0
				std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	for c in node.get_children():
		_scan_fade(c, tag, bad, must_solid)


func _clip_for(kind: String, phase: String) -> String:
	var table := {
		"bench": {"enter": "bench_sit_enter", "idle": "bench_sit_idle", "exit": "bench_sit_exit"},
		"log": {"enter": "log_sit_enter", "idle": "log_sit_idle", "exit": "log_sit_exit"},
		"hammock": {"enter": "hammock_enter", "idle": "hammock_sleep", "exit": "hammock_exit"},
	}
	if not table.has(kind):
		return "sit" if phase == "idle" else ""
	return str(table[kind][phase])


func _glide(pos: Vector3, yaw: float, stepping: bool = false) -> void:
	player.locked = true
	player.use_anchor = true
	var from := player.global_position
	var from_yaw := player.face_yaw
	var dist := from.distance_to(pos)
	var dur := clampf(dist / 0.85, 0.4, 0.9) if stepping else 0.45
	if stepping and player.boy != null:
		player.boy.play_clip("walk", 0.12)
		if player.boy.anim != null and dur > 0.05:
			player.boy.anim.speed_scale = clampf((dist / dur) / Constants.WALK_CLIP, 0.75, 1.25)
	var t := 0.0
	while t < dur:
		var dt := get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 30.0
		t += dt
		var k := smoothstep(0.0, 1.0, clampf(t / dur, 0.0, 1.0))
		player.anchor = from.lerp(pos, k)
		player.face_yaw = lerp_angle(from_yaw, yaw, k)
		player.rotation.y = player.face_yaw
		await get_tree().process_frame
	player.anchor = pos
	player.global_position = pos
	player.face_yaw = yaw
	player.rotation.y = yaw


func _wait_clip(limit: float) -> void:
	if player.boy == null or player.boy.anim == null:
		return
	var done := false
	var cb := func(_n: StringName) -> void:
		done = true
	player.boy.anim.animation_finished.connect(cb, CONNECT_ONE_SHOT)
	var start := Time.get_ticks_msec()
	while not done and Time.get_ticks_msec() - start < int(limit * 1000.0):
		var clip := player.boy.anim.get_animation(player.boy.anim.current_animation)
		if clip != null and player.boy.anim.current_animation_position >= clip.length - 0.08:
			break
		await get_tree().process_frame


func _throw() -> void:
	if _throwing or _sitting or player.boy == null or player.boy.arm == null:
		return
	var ends := IslandData.dock_ends()
	var p := player.global_position
	var on_tee := absf(p.x) < 3.2 and p.z < ends.y + 4.2 and p.z > ends.y - 1.0
	if not on_tee:
		return
	_throwing = true
	joy.value = Vector2.ZERO
	player.stick = Vector2.ZERO
	player.locked = true
	if player.boy.ik != null:
		player.boy.ik.paused = false
		player.boy.ik.both_down = true
		player.boy.ik.contact_y = Constants.DECK_Y
	player.boy.holding = true
	rig.framing = "throw"
	var sea := Vector3(0, 0, -1)
	player.face_yaw = atan2(-sea.x, -sea.z)
	player.rotation.y = player.face_yaw
	player.boy.arm.start(_crouch)


func _throw_release() -> void:
	await get_tree().create_timer(0.50).timeout
	if player == null or player.boy == null or player.boy.skel == null:
		return
	var skel: Skeleton3D = player.boy.skel
	var hand := skel.find_bone("mixamorig_RightHand")
	var origin := player.global_position + Vector3(0, 0.9, 0)
	if hand >= 0:
		origin = (skel.global_transform * skel.get_bone_global_pose(hand)).origin
	var fwd := Vector3(-sin(player.face_yaw), 0.0, -cos(player.face_yaw))
	var speed := 10.4 if _crouch else 11.2
	var lift := 1.15 if _crouch else 1.55
	_spawn_stone(origin + fwd * 0.25, fwd * speed + Vector3.UP * lift)
	await get_tree().create_timer(0.7).timeout
	_on_throw_done()


func _on_release(origin: Vector3, velocity: Vector3) -> void:
	call_deferred("_spawn_stone", origin, velocity)


var _ripples: Array[Vector4] = []


func add_ripple(at: Vector3) -> void:
	add_ripple_aged(at, 0.0)


func add_ripple_aged(at: Vector3, age: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_ripples.append(Vector4(at.x, at.z, now - age, 1.0))
	while _ripples.size() > 4:
		_ripples.pop_front()
	_push_ripples(now)


func _push_ripples(now: float) -> void:
	if water_mat == null:
		return
	var i := 0
	while i < _ripples.size():
		if now - _ripples[i].z >= 1.5:
			_ripples.remove_at(i)
		else:
			i += 1
	var slots := ["ripple0", "ripple1", "ripple2", "ripple3"]
	for s in 4:
		var v := Vector4(0, 0, 0, 0)
		if s < _ripples.size():
			v = _ripples[s]
		water_mat.set_shader_parameter(slots[s], v)


func _spawn_stone(origin: Vector3, velocity: Vector3) -> void:
	var stone := SkipStone.new()
	add_child(stone)
	stone.settled.connect(_on_stone_settled)
	stone.launch(origin, velocity, amb)
	hud.banner.text = "出手"


func _on_throw_done() -> void:
	_throwing = false
	player.locked = false
	player.boy.holding = false
	if player.boy.ik != null:
		player.boy.ik.paused = false
		player.boy.ik.both_down = false
		player.boy.ik.contact_y = 0.0
	rig.framing = ""


func _on_stone_settled(skips: int, dist: float) -> void:
	if skips == 5 or skips == 10 or skips == 15 or skips == 20:
		hud.banner.text = "%d 连跳" % skips
	else:
		hud.banner.text = "弹跳 %d 次 · %.1f 米" % [skips, dist]
	var better := skips > _best_skips or dist > _best_dist + 0.05
	_best_skips = maxi(_best_skips, skips)
	_best_dist = maxf(_best_dist, dist)
	hud.record.text = "最高纪录：弹跳 %d 次 · 最远 %.1f 米" % [_best_skips, _best_dist]
	if better:
		_save()


func _on_step(kind: String) -> void:
	amb.foot(kind)


func _load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") != OK:
		return
	night = bool(cf.get_value("game", "night", false))
	_best_skips = int(cf.get_value("game", "skips", 0))
	_best_dist = float(cf.get_value("game", "dist", 0.0))
	if hud != null:
		hud.record.text = "最高纪录：弹跳 %d 次 · 最远 %.1f 米" % [_best_skips, _best_dist]
	_apply_night()


func _apply_night() -> void:
	if sun == null:
		return
	sun.light_energy = 0.22 if night else 1.25
	sun.light_color = Color(0.62, 0.74, 1.0) if night else Color(1.0, 0.96, 0.88)
	if sky_mat != null:
		sky_mat.sky_top_color = Color(0.02, 0.05, 0.12) if night else Color(0.42, 0.68, 0.92)
		sky_mat.sky_horizon_color = Color(0.10, 0.16, 0.28) if night else Color(0.78, 0.88, 0.92)
		sky_mat.ground_horizon_color = Color(0.08, 0.12, 0.16) if night else Color(0.55, 0.72, 0.7)
	var envn := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if envn != null and envn.environment != null:
		envn.environment.ambient_light_energy = 0.18 if night else 0.55
		envn.environment.ambient_light_color = Color(0.35, 0.42, 0.62) if night else Color(0.72, 0.78, 0.74)
	props.apply_night(night)
	if hud != null:
		hud.night_btn.text = "白天" if night else "夜晚"


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "night", night)
	cf.set_value("game", "skips", _best_skips)
	cf.set_value("game", "dist", _best_dist)
	cf.save("user://settings.cfg")


func _ground_mat() -> ShaderMaterial:
	if ground == null:
		return null
	for c in ground.get_children():
		if c is MeshInstance3D:
			return (c as MeshInstance3D).material_override as ShaderMaterial
	return null


func _shot_name() -> String:
	var q := _query()
	var i := q.find("shot=")
	if i < 0:
		return ""
	var rest := q.substr(i + 5)
	var amp := rest.find("&")
	if amp >= 0:
		rest = rest.substr(0, amp)
	return rest


func _pose_shot() -> void:
	for _i in 12:
		await get_tree().process_frame
	if player == null or player.boy == null:
		return
	var ends := IslandData.dock_ends()
	var name := _shot_name()
	player.locked = true
	player.speed = 0.0
	fader.enabled = false
	rig.set_process(false)
	rig.cam.fov = 48.0
	var cam: Camera3D = rig.cam
	var tee := Vector3(0.0, Constants.DECK_Y, ends.y + 1.3)
	if name == "near":
		_put(tee, 0.0)
		fader.enabled = true
		rig.yaw = 0.55
		rig.pitch = Constants.CAM_PITCH
		rig.dist = Constants.CAM_DIST
		rig.set_process(true)
		for _k in 24:
			await get_tree().process_frame
		print("SHOT_READY near")
		return
	if name == "face":
		_put(tee, PI)
		if player.boy.ik != null:
			player.boy.ik.paused = true
		player.boy.set_speed(0.0)
		_cam(cam, tee + Vector3(0.15, 1.15, 1.15), tee + Vector3(0, 0.95, 0))
		print("SHOT_READY face")
		return
	if name == "occ" or name.begins_with("occ_f"):
		var shore := ends.x
		var step := 0
		if name.begins_with("occ_f"):
			step = int(name.substr(5))
		var start := Vector3(0.7, 0.0, shore + 2.5)
		var goal := Vector3(1.5, 0.0, shore + 1.3)
		var occ := start.lerp(goal, clampf(float(step) / 7.0, 0.0, 1.0))
		var gy: float = ground.height(occ.x, occ.z)
		if gy > -2.0:
			occ.y = gy
		_put(occ, 0.0)
		player.boy.play_clip("walk", 0.0)
		if player.boy.anim != null:
			player.boy.anim.seek(0.12 + float(step) * 0.08, true)
			player.boy.anim.pause()
		if not _query().contains("occ=0"):
			fader.enabled = true
		# 35° down, tall-phone field, so the hut fits on the right and the palm row on the left.
		cam.fov = 80.0
		_cam(cam, Vector3(-0.2, 4.7, shore + 7.0), Vector3(2.0, 1.4, shore + 1.5))
		var settle := 0 if name == "occ" else 2 + step * 6
		for _k in settle:
			await get_tree().process_frame
		print("SHOT_READY ", name)
		return
	if name == "pace":
		dbg.on = true
		dbg.visible = true
		dbg.log_pace = true
		_put(Vector3(0.15, Constants.DECK_Y, ends.y + 7.5), PI)
		player.locked = false
		if player.boy.ik != null:
			player.boy.ik.paused = false
		rig.follow = true
		rig.yaw = PI
		rig.pitch = Constants.CAM_PITCH
		rig.dist = Constants.CAM_DIST
		rig.set_process(true)
		joy.value = Vector2(0, -1)
		player.stick = joy.value
		for _i in 120:
			await get_tree().process_frame
		print("PACE_DONE n=%d" % dbg.walk_ms.size())
		print("SHOT_READY pace")
		return
	if name == "walk":
		_put(Vector3(0.15, Constants.DECK_Y, ends.y + 3.2), 0.0)
		player.locked = false
		player.boy.holding = false
		if player.boy.ik != null:
			player.boy.ik.paused = false
		player.boy.set_speed(0.64)
		rig.set_process(true)
		print("SHOT_READY walk")
		return
	if name.begins_with("loc_"):
		var step := int(name.substr(4))
		# Mid-dock, facing inland, so a run stays on the planks.
		_put(Vector3(0.15, Constants.DECK_Y, ends.y + 7.5), PI)
		player.locked = false
		if player.boy.ik != null:
			player.boy.ik.paused = false
			player.boy.ik.both_down = false
		rig.follow = true
		rig.looking = false
		rig.hold_pitch = false
		rig.yaw = PI
		rig.pitch = Constants.CAM_PITCH
		rig.dist = Constants.CAM_DIST
		rig.set_process(true)
		var mag := 0.0
		var frames := 8
		if step == 1:
			mag = 0.55
			frames = 14
		elif step == 2:
			mag = 0.55
			frames = 48
		elif step == 3:
			mag = 1.0
			frames = 24
		elif step == 4:
			mag = 1.0
			frames = 36
		elif step == 5:
			joy.value = Vector2(0, -1)
			player.stick = joy.value
			for _i in 40:
				await get_tree().process_frame
			joy.value = Vector2.ZERO
			player.stick = Vector2.ZERO
			for _i in 16:
				await get_tree().process_frame
			print("SHOT_READY ", name)
			return
		joy.value = Vector2(0, -mag)
		player.stick = joy.value
		for _i in frames:
			await get_tree().process_frame
		print("SHOT_READY ", name)
		return
	if name.begins_with("orbit_"):
		var step := int(name.substr(6))
		_put(tee, 0.0)
		player.locked = true
		rig.follow = false
		rig.looking = false
		rig.hold_pitch = false
		rig.yaw = float(step) * TAU / 4.0
		rig.pitch = Constants.CAM_PITCH
		rig.dist = Constants.CAM_DIST
		rig.set_process(true)
		for _i in 8:
			await get_tree().process_frame
		print("SHOT_READY ", name)
		return
	if name.begins_with("throw_"):
		_put(tee, 0.0)
		if player.boy.ik != null:
			player.boy.ik.paused = false
			player.boy.ik.both_down = true
			player.boy.ik.contact_y = Constants.DECK_Y
		player.boy.arm.playing = true
		player.boy.arm.hold = true
		player.boy.arm.crouch = name == "throw_crouch"
		var phases := {
			"throw_windup": 0.16, "throw_whip": 0.48, "throw_release": 0.62, "throw_follow": 0.92, "throw_crouch": 0.44,
			"throw_s0": 0.18, "throw_s1": 0.30, "throw_s2": 0.40, "throw_s3": 0.50,
			"throw_s4": 0.60, "throw_s5": 0.72, "throw_s6": 0.84, "throw_s7": 0.96,
		}
		player.boy.arm.phase = float(phases.get(name, 0.48))
		for _i in 6:
			await get_tree().process_frame
		var p := player.global_position
		# Wide enough that the hand and the first two skips share the frame.
		_throw_view(cam, p)
		if _query().contains("proxy=1"):
			_show_proxy_only()
		_show_flight(cam, name)
		print("SHOT_READY ", name)
		return
	if name.begins_with("skip_"):
		var step := int(name.substr(5))
		_put(tee, 0.0)
		if player.boy.ik != null:
			player.boy.ik.paused = false
			player.boy.ik.both_down = true
			player.boy.ik.contact_y = Constants.DECK_Y
		player.boy.arm.playing = true
		player.boy.arm.hold = true
		var phases := [0.34, 0.56, 0.64, 0.70, 0.82, 0.96]
		player.boy.arm.phase = float(phases[mini(step, 5)])
		for _i in 4:
			await get_tree().process_frame
		var p := player.global_position
		_throw_view(cam, p)
		_show_skip(cam, p, step)
		print("SHOT_READY ", name)
		return
	if name.begins_with("bench_s") or name.begins_with("ham_s"):
		var bench := name.begins_with("bench_s")
		var step := int(name.substr(7 if bench else 5))
		var seat := "Bench" if bench else "Hammock"
		var item := _seat_named(seat)
		if item == null:
			print("SHOT_READY ", name)
			return
		var clips: Array[String] = []
		if bench:
			clips = ["", "bench_sit_idle", "bench_lie", ""]
		else:
			clips = ["", "hammock_sleep", "hammock_sleep", ""]
		if step == 0 or step == 3:
			var beside := item.global_position + Vector3(-1.1, 0, 1.2)
			var gy: float = ground.height(beside.x, beside.z)
			if gy > -1.5:
				beside.y = gy
			_put(beside, float(item.get_meta("yaw", 0.0)))
			if player.boy.ik != null:
				player.boy.ik.paused = false
			player.boy.clear_hold()
		else:
			_put_on_seat(seat)
			if player.boy.ik != null:
				player.boy.ik.paused = true
			player.boy.play_clip(clips[step], 0.0)
			if player.boy.anim != null:
				player.boy.anim.seek(0.35 if step == 1 else 0.7, true)
				player.boy.anim.pause()
		for _i in 4:
			await get_tree().process_frame
		var c := item.global_position
		if bench and step == 2:
			_apply_bench_lie(item)
			for _k in 2:
				await get_tree().process_frame
			_frame_bench(cam, item.global_position)
		else:
			_cam(cam, c + Vector3(-2.8, 1.7, 2.6), c + Vector3(0, 0.7, 0))
		print("SHOT_READY ", name)
		return
	if name == "bench_lie" or name == "lounger" or name == "hammock_rest":
		var seat_name: String = {"bench_lie": "Bench", "lounger": "Lounger", "hammock_rest": "Hammock"}[name]
		var clip: String = {"bench_lie": "hammock_sleep", "lounger": "lounger_lie", "hammock_rest": "hammock_sleep"}[name]
		_put_on_seat(seat_name)
		if player.boy.ik != null:
			player.boy.ik.paused = true
		player.boy.play_clip(clip, 0.0)
		if player.boy.anim != null:
			player.boy.anim.seek(0.6, true)
			player.boy.anim.pause()
		for _i in 4:
			await get_tree().process_frame
		var p := player.global_position
		var yaw := player.face_yaw
		var face := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var side := Vector3(face.z, 0.0, -face.x)
		if name == "hammock_rest":
			var ham := _seat_named("Hammock")
			var c := ham.global_position if ham != null else p
			_cam(cam, c + Vector3(0.15, 1.65, 3.1), c + Vector3(0, 0.75, 0))
		elif name == "bench_lie":
			_cam(cam, p + side * 3.4 + Vector3(0, 1.9, 0) + face * 1.2, p + Vector3(0, 0.4, 0))
		else:
			_frame_for_shot(cam)
		print("SHOT_READY ", name)
		return
	var spot := tee
	var look := Vector3(1.5, 1.2, 4.0)
	var eye := Vector3(-5.5, 5.2, -7.5)
	if name == "pier":
		spot = Vector3(0.2, 0.0, ends.x + 0.6)
	elif name == "hut":
		var hut := _seat_named("Hut")
		spot = hut.global_position + Vector3(-1.6, 0, 2.2) if hut != null else spot
		eye = Vector3(-3.2, 2.6, 3.4)
		look = Vector3(1.2, 1.3, -0.4)
	elif name == "hammock":
		var ham := _seat_named("Hammock")
		spot = ham.global_position + Vector3(-1.8, 0, 1.6) if ham != null else spot
		eye = Vector3(-3.2, 2.6, 3.4)
		look = Vector3(1.2, 1.3, -0.4)
	if name != "spawn":
		var gy: float = ground.height(spot.x, spot.z)
		if gy > -2.0:
			spot.y = gy
	_put(spot, PI)
	_cam(cam, spot + eye, spot + look)
	print("SHOT_READY ", name)


func _seat_named(node_name: String) -> Fadable:
	for item in props.items:
		if item.name == node_name:
			return item
	return null


func _show_proxy_only() -> void:
	var skel: Skeleton3D = player.boy.skel
	if skel == null:
		return
	var proxy := skel.get_node_or_null("ShadowProxy") as MeshInstance3D
	if proxy == null:
		return
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.55, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	proxy.material_override = mat
	_hide_color_meshes(player.boy.model)


func _hide_color_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).visible = false
	for c in node.get_children():
		_hide_color_meshes(c)


func _show_throw_stone(shot: String) -> void:
	var skel: Skeleton3D = player.boy.skel
	if skel == null:
		return
	var hand := skel.find_bone("mixamorig_RightHand")
	if hand < 0:
		return
	var xf := skel.global_transform * skel.get_bone_global_pose(hand)
	var elbow := skel.find_bone("mixamorig_RightForeArm")
	var origin := xf.origin
	var palm := Vector3.ZERO
	if elbow >= 0:
		var ep := (skel.global_transform * skel.get_bone_global_pose(elbow)).origin
		palm = origin - ep
		if palm.length_squared() > 1e-6:
			origin += palm.normalized() * 0.12
	# The throw camera sits on -X/+Z. Push the stone out of the fist toward that camera.
	origin += Vector3(-1.85, 0.35, 2.15).normalized() * 0.2
	var fwd := Vector3(-sin(player.face_yaw), 0.0, -cos(player.face_yaw))
	var phase := 0.0
	var phase_map := {
		"throw_release": 0.62, "throw_follow": 0.92, "throw_whip": 0.48,
		"throw_s0": 0.18, "throw_s1": 0.30, "throw_s2": 0.40, "throw_s3": 0.50,
		"throw_s4": 0.60, "throw_s5": 0.72, "throw_s6": 0.84, "throw_s7": 0.96,
	}
	if phase_map.has(shot):
		phase = float(phase_map[shot])
	if phase >= 0.48:
		var out := clampf((phase - 0.46) / 0.36, 0.0, 1.0)
		# Straight and flat toward the water, about knee height.
		origin += fwd * (0.05 + out * 0.55)
		origin.y = player.global_position.y + 0.40
	var stone := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.11
	mesh.height = 0.22
	stone.mesh = mesh
	stone.scale = Vector3(1.25, 0.28, 1.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.16, 0.15, 0.14)
	stone.material_override = mat
	stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stone)
	stone.global_position = origin


func _throw_view(cam: Camera3D, p: Vector3) -> void:
	# Boy in the lower frame, open water above him, release and the first skips together.
	_cam(cam, p + Vector3(-2.4, 1.55, 2.7), p + Vector3(0.15, 0.6, -0.7))


func _skip_spot(p: Vector3, ahead: float, side: float) -> Vector3:
	var yaw := player.face_yaw
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	return p + fwd * ahead + right * side + Vector3(0, 0.12, 0)


func _sea_at(cam: Camera3D, sx: float, sy: float) -> Vector3:
	var vp := get_viewport().get_visible_rect().size
	var px := Vector2(vp.x * sx, vp.y * sy)
	var origin := cam.project_ray_origin(px)
	var dir := cam.project_ray_normal(px)
	if absf(dir.y) < 0.0001:
		return origin
	var t := (0.08 - origin.y) / dir.y
	return origin + dir * maxf(t, 0.05)


func _grip_pos(p: Vector3) -> Vector3:
	if player.boy == null or player.boy.skel == null:
		return p + Vector3(0, 0.7, -0.2)
	var grip := player.boy.skel.get_node_or_null("PebbleGrip") as Node3D
	if grip != null:
		return grip.global_position
	return p + Vector3(0, 0.7, -0.2)


func _show_flight(cam: Camera3D, shot: String) -> void:
	var phase_map := {
		"throw_s0": 0.18, "throw_s1": 0.30, "throw_s2": 0.40, "throw_s3": 0.50,
		"throw_s4": 0.60, "throw_s5": 0.72, "throw_s6": 0.84, "throw_s7": 0.96,
	}
	var phase := float(phase_map.get(shot, 0.3))
	if phase < 0.52 or player.boy == null:
		return
	if player.boy.pebble != null:
		player.boy.pebble.visible = false
	var hand := _grip_pos(player.global_position)
	var skip_a := _skip_spot(player.global_position, 2.8, -1.3)
	var skip_b := _skip_spot(player.global_position, 3.7, -0.9)
	var pos := hand
	if phase < 0.68:
		var t := clampf((phase - 0.52) / 0.16, 0.0, 1.0)
		pos = hand.lerp(skip_a, t)
		pos.y = lerpf(hand.y, 0.22, t) + sin(t * PI) * 0.28
	else:
		var t2 := clampf((phase - 0.68) / 0.22, 0.0, 1.0)
		pos = skip_a.lerp(skip_b, t2)
		pos.y = 0.2 + sin(t2 * PI) * 0.22
		if t2 < 0.15:
			_impact(skip_a, 0.08, true, false)
	_place_pebble(pos, phase >= 0.7)
	_trail(hand, pos)


func _show_skip(cam: Camera3D, p: Vector3, step: int) -> void:
	var hand := _grip_pos(p)
	var skip_a := _skip_spot(p, 2.8, -1.3)
	var skip_b := _skip_spot(p, 3.7, -0.9)
	if step <= 0:
		return
	if player.boy.pebble != null and step >= 1:
		player.boy.pebble.visible = false
	if step == 1:
		var pos := hand.lerp(skip_a, 0.72)
		pos.y = 0.34
		_place_pebble(pos)
		_trail(hand, pos)
		return
	if step == 2:
		_place_pebble(skip_a + Vector3(0, 0.2, 0))
		_impact(skip_a, 0.06, true, false)
		_trail(hand, skip_a)
	elif step == 3:
		var mid := skip_a.lerp(skip_b, 0.45)
		mid.y = 0.28
		_place_pebble(mid, true)
		_trail(skip_a, mid)
		_impact(skip_a, 0.42, false, true)
	elif step == 4:
		_place_pebble(skip_b + Vector3(0, 0.2, 0), true)
		_impact(skip_b, 0.06, true, false)
		_impact(skip_a, 0.72, false, true)
		_trail(skip_a, skip_b)
	else:
		var onward := skip_b + (skip_b - skip_a).normalized() * 0.35
		onward.y = 0.12
		_place_pebble(onward, true)
		_column(skip_b)
		_impact(skip_b, 0.08, true, true)
		_impact(skip_a, 0.9, false, true)


func _impact(at: Vector3, age: float, crown: bool, foam_on: bool) -> void:
	add_ripple_aged(at, age)
	if age < 0.35:
		_contact_shadow(at, lerpf(0.75, 0.25, age / 0.35))
	if crown:
		_spray(at)
	if foam_on and age < 1.05:
		var grow := clampf(age / 0.5, 0.35, 1.0)
		_foam(at, (1.0 - smoothstep(0.15, 1.05, age)) * 0.62, 0.4 + grow * 0.3)


func _trail(a: Vector3, b: Vector3) -> void:
	for i in 12:
		var t := float(i + 1) / 13.0
		var crumb := _soft_crumb(b.lerp(a, t))
		var mat := crumb.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = 0.5 * (1.0 - t)


func _place_pebble(at: Vector3, wet: bool = false) -> MeshInstance3D:
	var stone := MeshInstance3D.new()
	stone.mesh = PebbleMesh.mesh()
	stone.material_override = BoyVisual.pebble_mat(wet)
	stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stone)
	stone.global_position = at
	return stone


func _soft_crumb(at: Vector3) -> MeshInstance3D:
	var bit := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.032
	mesh.height = 0.064
	mesh.radial_segments = 6
	mesh.rings = 3
	bit.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.96, 0.95, 0.9, 0.5)
	bit.material_override = mat
	bit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bit)
	bit.global_position = at
	return bit


func _contact_shadow(at: Vector3, alpha: float) -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.11
	mesh.bottom_radius = 0.11
	mesh.height = 0.006
	mesh.radial_segments = 12
	disc.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.02, 0.04, 0.06, alpha)
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	disc.global_position = Vector3(at.x, 0.11, at.z)


func _foam(at: Vector3, alpha: float, radius: float) -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.008
	mesh.radial_segments = 16
	disc.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.97, 0.99, 1.0, alpha)
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	disc.global_position = Vector3(at.x, 0.125, at.z)


func _column(at: Vector3) -> void:
	var col := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.08
	mesh.height = 0.7
	mesh.radial_segments = 8
	col.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.96, 0.98, 1.0, 0.8)
	col.material_override = mat
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(col)
	col.global_position = Vector3(at.x, 0.4, at.z)


func _spray(at: Vector3) -> void:
	for i in 14:
		var drop := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.055 if i < 10 else 0.04
		mesh.height = mesh.radius * 2.0
		mesh.radial_segments = 6
		mesh.rings = 3
		drop.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 1, 1)
		drop.material_override = mat
		drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(drop)
		var ang := TAU * float(i) / 10.0
		if i < 10:
			drop.global_position = at + Vector3(cos(ang) * 0.62, 0.38 + float(i % 3) * 0.08, sin(ang) * 0.62)
		else:
			var a2 := TAU * float(i) / 4.0
			drop.global_position = at + Vector3(cos(a2) * 0.18, 0.72, sin(a2) * 0.18)


func _bone_world(bone_name: String) -> Vector3:
	var skel: Skeleton3D = player.boy.skel
	var i := skel.find_bone(bone_name)
	if i < 0:
		return player.global_position
	return (skel.global_transform * skel.get_bone_global_pose(i)).origin


func _apply_bench_lie(item: Fadable) -> void:
	player.face_yaw = 0.0
	player.rotation.y = 0.0
	player.locked = true
	if player.boy.ik != null:
		player.boy.ik.paused = true
	player.boy.lay_flat("bench")
	var c := item.global_position
	player.global_position = c + Vector3(0.0, 0.7, 0.04)


func _snap_bench(c: Vector3) -> void:
	var head := _bone_world("mixamorig_Head")
	var hips := _bone_world("mixamorig_Hips")
	# Head bone near the +X end. Hips sit just above the slats so the back touches.
	var dx := (c.x + 0.55) - head.x
	var dy := (c.y + 0.52) - hips.y
	var dz := (c.z + 0.02) - hips.z
	player.global_position += Vector3(dx, dy, dz)
	player.anchor = player.global_position
	player.use_anchor = true


func _frame_bench(cam: Camera3D, c: Vector3) -> void:
	_snap_bench(c)
	var head := _bone_world("mixamorig_Head")
	var foot := _bone_world("mixamorig_LeftFoot")
	var hips := _bone_world("mixamorig_Hips")
	print("LIE head=", head, " hips=", hips, " foot=", foot, " bench=", c)
	var mid := (head + foot) * 0.5
	var along := foot - head
	along.y = 0.0
	if along.length() < 0.2:
		along = Vector3(1, 0, 0)
	var side := Vector3(-along.z, 0.0, along.x).normalized()
	if side.z < 0.0:
		side = -side
	var dist := along.length() / (2.0 * tan(deg_to_rad(12.0))) * 1.35
	dist = clampf(dist, 3.4, 8.5)
	_cam(cam, mid + side * dist + Vector3(0, 0.9, 0), mid + Vector3(0, 0.05, 0))


func _shot_ring(at: Vector3, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.72
	mesh.outer_radius = radius
	mesh.rings = 10
	mesh.ring_segments = 8
	ring.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.97, 0.99, 1.0, 0.95)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = at


func _seat_pos(item: Fadable) -> Vector3:
	var local: Vector3 = item.get_meta("seat_local", Vector3.ZERO)
	var pos: Vector3 = item.global_transform * local
	if bool(item.get_meta("on_prop", false)):
		pos.y += float(item.get_meta("lift", 0.0))
		return pos
	var gy: float = ground.height(pos.x, pos.z)
	if gy > -1.5:
		pos.y = gy
	else:
		pos.y = item.global_position.y
	pos.y += float(item.get_meta("lift", 0.0))
	return pos


func _put_on_seat(node_name: String) -> void:
	var item := _seat_named(node_name)
	if item == null:
		return
	var yaw := float(item.get_meta("yaw", 0.0))
	_put(_seat_pos(item), yaw)


func _put(spot: Vector3, yaw: float) -> void:
	player.global_position = spot
	player.anchor = spot
	player.use_anchor = true
	player.face_yaw = yaw
	player.rotation.y = yaw
	player.reset_physics_interpolation()


func _cam(cam: Camera3D, eye: Vector3, at: Vector3) -> void:
	cam.global_position = eye
	cam.look_at(at, Vector3.UP)


func _frame_for_shot(cam: Camera3D) -> void:
	var p := player.global_position
	var yaw := player.face_yaw
	var face := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var side := Vector3(face.z, 0.0, -face.x)
	_cam(cam, p + side * 3.4 + Vector3(0, 1.45, 0) + face * 1.1, p + Vector3(0, 0.55, 0))


func _query() -> String:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("window.location.search", true)
		return str(v)
	var acc := ""
	for a in OS.get_cmdline_user_args():
		acc += str(a)
	return acc
