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
	props = Props.new()
	add_child(props)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 90)
	plane.subdivide_width = 16
	plane.subdivide_depth = 16
	water.mesh = plane
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/sea.gdshader")
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var nk := 1.0 if night else 0.0
	if water_mat != null:
		water_mat.set_shader_parameter("game_time", t)
		water_mat.set_shader_parameter("night_k", nk)
	var gmat := _ground_mat()
	if gmat != null:
		gmat.set_shader_parameter("game_time", t)
		gmat.set_shader_parameter("night_k", nk)
	if not live:
		return
	player.stick = joy.value
	_prompts()
	if dbg != null:
		dbg.note(delta, player.speed > 0.12)


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
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if joy.drag(drag):
			player.stick = joy.value
			return
		if drag.index == _orbit:
			rig.yaw -= drag.relative.x * 0.006
	elif event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_W:
			joy.value = Vector2(0, -1)
		elif k.keycode == KEY_S:
			joy.value = Vector2(0, 1)


func _prompts() -> void:
	var p := player.global_position
	var ends := IslandData.dock_ends()
	var on_tee := absf(p.x) < 3.2 and p.z < ends.y + 4.2 and p.z > ends.y - 1.0
	var busy := _sitting or _throwing
	hud.throw_btn.visible = on_tee and not busy
	hud.pose_btn.visible = on_tee and not busy
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
	hud.lie_btn.visible = _sitting and seated and player.boy != null and player.boy.rest != null and player.boy.rest.mode != "lie"
	hud.up_btn.visible = _sitting and not _throwing


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
		rig.pitch = deg_to_rad(50.0)
	elif name == "固定视角":
		pass
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
	_rest_item = item
	rest_kind = str(item.get_meta("kind", ""))
	joy.value = Vector2.ZERO
	player.stick = Vector2.ZERO
	player.locked = true
	var yaw := float(item.get_meta("yaw", 0.0))
	var pos := _seat_pos(item)
	rig.framing = "front"
	rig.yaw = yaw + PI
	rig.pivot_y = 0.45 if rest_kind == "towel" or rest_kind == "lounger" or rest_kind == "hammock" else 0.7
	await _glide(pos, yaw)
	if rest_kind == "lounger" or rest_kind == "towel":
		player.boy.play_clip("lounger_lie", 0.2)
		return
	var enter := _clip_for(rest_kind, "enter")
	var idle := _clip_for(rest_kind, "idle")
	if enter != "":
		player.boy.play_clip(enter, 0.15)
		await _wait_clip(8.0 if rest_kind != "hammock" else 12.0)
	if idle != "":
		player.boy.play_clip(idle, 0.2)
	else:
		player.boy.play_clip("sit", 0.2)


func _begin_lie() -> void:
	if player.boy == null:
		return
	if player.boy.rest != null:
		player.boy.rest.mode = ""
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
	if player.boy != null:
		player.boy.clear_hold()
	var back := player.global_position
	var yaw := player.face_yaw
	var step := Vector3(-sin(yaw), 0, -cos(yaw)) * -0.55
	await _glide(back + step, yaw)
	_sitting = false
	rest_kind = ""
	_rest_item = null
	player.locked = false
	player.use_anchor = false
	rig.framing = ""
	rig.pivot_y = 0.62


func _clip_for(kind: String, phase: String) -> String:
	var table := {
		"bench": {"enter": "bench_sit_enter", "idle": "bench_sit_idle", "exit": "bench_sit_exit"},
		"log": {"enter": "log_sit_enter", "idle": "log_sit_idle", "exit": "log_sit_exit"},
		"hammock": {"enter": "hammock_enter", "idle": "hammock_sleep", "exit": "hammock_exit"},
	}
	if not table.has(kind):
		return "sit" if phase == "idle" else ""
	return str(table[kind][phase])


func _glide(pos: Vector3, yaw: float) -> void:
	player.locked = true
	player.use_anchor = true
	var from := player.global_position
	var from_yaw := player.face_yaw
	var t := 0.0
	while t < 0.45:
		var dt := get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 30.0
		t += dt
		var k := smoothstep(0.0, 1.0, clampf(t / 0.45, 0.0, 1.0))
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
	var t := 0.0
	while not done and t < limit:
		var dt := get_process_delta_time()
		t += 0.05 if dt <= 0.0 else dt
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
	rig.framing = "side"
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
		# Close 3/4 on his throwing side, low enough that the crouch and the stone read.
		_cam(cam, p + Vector3(-1.85, 0.98, 2.15), p + Vector3(0.0, 0.5, -0.15))
		if _query().contains("proxy=1"):
			_show_proxy_only()
		_show_throw_stone(name)
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
	# Pull the stone toward the camera so it sits outside the hand, not inside the mesh.
	origin += Vector3(-0.62, 0.2, 0.72).normalized() * 0.09
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
	mesh.radius = 0.078
	mesh.height = 0.156
	stone.mesh = mesh
	stone.scale = Vector3(1.25, 0.32, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.86, 0.88, 0.90)
	stone.material_override = mat
	stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stone)
	stone.global_position = origin


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
