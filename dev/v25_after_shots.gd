extends SceneTree
## v25 after-fix: authored bench/log/hammock clips at 390×844.
## Captures default game camera + close views; montages under screenshots/v25/after/.

const OUT := "/workspace/screenshots/v25/after"
const W := 390
const H := 844
const BUILD_ID := "v25-clips-02"


func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(W, H))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(W, H)
	DirAccess.make_dir_recursive_absolute(OUT)
	for d in ["walk", "run", "bench", "log", "hammock", "faces", "camera", "scene", "crops"]:
		DirAccess.make_dir_recursive_absolute(OUT + "/" + d)

	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 60:
		await process_frame
	m.demo_mode = true
	m.demo_cam = true
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
	m.ui_root.visible = false
	if m.zzz and is_instance_valid(m.zzz):
		m.zzz.visible = false
	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 60:
			await process_frame

	print("V25_AFTER_BUILD ", BUILD_ID,
		" clips=", m.boy.ap.has_animation("bench_sit_enter") if m.boy.ap else false,
		" hammock_v25=", m.island.hammock_use_v25)
	await _gait_seq(m, vp, "walk", 1.15, 0.0)
	await _gait_seq(m, vp, "run", 2.2, 1.0)
	await _prop_seq(m, vp, "bench", "长椅")
	await _prop_seq(m, vp, "log", "坐木")
	await _hammock_seq(m, vp)
	await _faces(m, vp)
	await _camera_zoom(m, vp)
	await _scenes(m, vp)
	print("V25_AFTER_SHOTS_DONE ", BUILD_ID)
	quit(0)


func _cam(m, look: Vector3, yaw: float, dist: float, pitch: float) -> void:
	m.demo_cam = true
	m.cam_fixed = true
	m.cam_target = look
	m.cam_yaw = yaw
	m.cam_pitch = pitch
	m.fix_dist = dist
	m.cam_dist = dist


func _shot(vp, path: String) -> Image:
	var tex = vp.get_texture()
	if tex == null:
		push_error("null viewport " + path)
		return null
	var img: Image = tex.get_image()
	if img == null:
		return null
	img.set_pixel(0, 0, Color(0.91, 0.12, 0.74, 1.0))
	img.set_pixel(1, 0, Color(0.12, 0.91, 0.55, 1.0))
	img.set_pixel(0, 1, Color(0.95, 0.85, 0.10, 1.0))
	img.save_png(path)
	print("SHOT ", path)
	return img


func _montage_imgs(imgs: Array, out_name: String) -> void:
	var n: int = imgs.size()
	if n == 0:
		return
	var strip := Image.create(W * n, H, false, Image.FORMAT_RGBA8)
	for i in n:
		var img: Image = imgs[i]
		if img == null:
			continue
		strip.blit_rect(img, Rect2i(0, 0, mini(W, img.get_width()), mini(H, img.get_height())), Vector2i(i * W, 0))
	strip.save_png("%s/%s" % [OUT, out_name])
	print("MONTAGE ", out_name)


func _gait_seq(m, vp, tag: String, speed: float, run_k: float) -> void:
	m.mode = m.Mode.EXPLORE
	m.rest_use_clips = false
	m._place(Vector3(3.2, 0, -7.2), 0.0)
	m.face_yaw = 0.0
	m.boy.rotation = Vector3.ZERO
	m.boy.end_prop_clip(0.0)
	m.boy.set_idle()
	m.boy.end_activity()
	for _i in 8:
		await process_frame
	m.boy.anim = "move"
	m.boy.set_move(speed)
	m.boy.move_w = 1.0
	m.boy.run_k = run_k
	for _w in 20:
		var dt: float = 1.0 / 30.0
		m.boy.set_move(speed)
		m.boy.move_w = 1.0
		m.boy.run_k = run_k
		m.player.global_position.x += speed * dt
		m.boy.global_position = m.player.global_position
		m.boy._tick(dt)
		await process_frame
	var imgs: Array = []
	for f in 8:
		var dt2: float = 1.0 / 30.0
		m.boy.set_move(speed)
		m.boy.move_w = 1.0
		m.boy.run_k = run_k
		m.player.global_position.x += speed * dt2
		m.boy.global_position = m.player.global_position
		m.boy._tick(dt2)
		m.boy.bake_pose_mesh()
		var look: Vector3 = m.player.global_position + Vector3(0, 0.55, 0)
		_cam(m, look, PI + 0.55, 3.1 if tag == "walk" else 3.4, 0.12)
		for _r in 3:
			m._apply_camera()
			await process_frame
		imgs.append(await _shot(vp, "%s/%s/f%02d.png" % [OUT, tag, f]))
		m.boy.restore_pose_mesh()
	_montage_imgs(imgs, "%s_8frame.png" % tag)


func _pick_seat(m, want_name: String) -> int:
	var best := -1
	var best_d := -1.0
	for i in m.island.seats.size():
		var cand: Dictionary = m.island.seats[i]
		if String(cand["name"]) != want_name:
			continue
		if want_name == "坐木":
			var d: float = (cand["top"] as Vector3).distance_to(m.island.campfire_pos)
			if d > best_d:
				best_d = d
				best = i
		else:
			return i
	return maxi(best, 0)


func _hold_clip(m, seconds: float) -> void:
	m.boy.seek_prop_clip(seconds)
	m.boy._tick(0.0)
	if m.rest_clip_prop == "hammock":
		m._sync_hammock_cloth_to_boy()
	for _i in 4:
		await process_frame


func _game_cam_rest(m) -> void:
	# Approximate default follow cam behind the boy.
	m.demo_cam = false
	m.cam_fixed = false
	m.ex_yaw = m.face_yaw + PI
	m.cam_yaw = m.ex_yaw
	m.cam_pitch = 0.18
	m.view_dist = 4.2
	m.cam_dist = 4.2
	m._apply_camera()


func _prop_seq(m, vp, tag: String, seat_name: String) -> void:
	var bi: int = _pick_seat(m, seat_name)
	var st: Dictionary = m.island.seats[bi]
	var face: Vector3 = st["face"].normalized()
	m.seat_i = bi
	m.seat_ap = st["approach"]
	m.seat_face = face
	m.rest_frozen = false
	m._begin_rest("seat")
	if not m.rest_use_clips:
		push_error("expected clip rest for " + tag)
		return
	m.rest_frozen = true
	# Snap onto enter (skip walk for shots).
	m.rest_phase = 1
	m._play_rest_enter_clip()
	var enter_len: float = m.boy.prop_clip_length()
	var exit_len := 2.5
	# Prop-frame side: +X shows seat depth (−Z) and shins past the front edge.
	# Do NOT bake_pose_mesh here — the static bake can drift vs live skin + props.
	var side: Vector3 = m.rest_prop_xf.basis.x.normalized()
	var yaw_front: float = atan2(face.x, face.z)
	var yaw_side: float = atan2(side.x, side.z)
	var imgs: Array = []
	var times_enter := [0.15, enter_len * 0.35, enter_len * 0.55, enter_len * 0.85, enter_len - 0.05]
	var labels_enter := ["enter_0", "enter_1", "enter_2", "enter_3", "enter_end"]
	for i in times_enter.size():
		await _hold_clip(m, times_enter[i])
		var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		# Default-ish game camera
		_game_cam_rest(m)
		for _r in 3:
			m._apply_camera()
			await process_frame
		await _shot(vp, "%s/%s/%s_game.png" % [OUT, tag, labels_enter[i]])
		# Close front
		_cam(m, hips + Vector3(0, 0.22, 0), yaw_front, 2.9, 0.14)
		for _r in 4:
			m._apply_camera()
			await process_frame
		await _shot(vp, "%s/%s/%s_front.png" % [OUT, tag, labels_enter[i]])
		# Close side — montage uses side so seat-depth / shin hang matches Blender previews.
		_cam(m, hips + Vector3(0, 0.20, 0), yaw_side, 2.55, 0.10)
		for _r in 4:
			m._apply_camera()
			await process_frame
		var img = await _shot(vp, "%s/%s/%s_side.png" % [OUT, tag, labels_enter[i]])
		if i == 0 or i == 2 or i == 4:
			imgs.append(img)

	# Idle loop
	m.rest_phase = 4
	m._play_rest_idle_clip()
	for tsec in [0.3, 2.0, 4.5]:
		await _hold_clip(m, tsec)
		var hips2: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		_game_cam_rest(m)
		for _r in 3:
			m._apply_camera()
			await process_frame
		await _shot(vp, "%s/%s/idle_%.0f_game.png" % [OUT, tag, tsec * 10.0])
		_cam(m, hips2 + Vector3(0, 0.22, 0), yaw_front, 2.85, 0.12)
		for _r in 4:
			m._apply_camera()
			await process_frame
		await _shot(vp, "%s/%s/idle_%.0f_front.png" % [OUT, tag, tsec * 10.0])
		_cam(m, hips2 + Vector3(0, 0.20, 0), yaw_side, 2.55, 0.10)
		for _r in 4:
			m._apply_camera()
			await process_frame
		imgs.append(await _shot(vp, "%s/%s/idle_%.0f_side.png" % [OUT, tag, tsec * 10.0]))

	# Exit
	m.rest_phase = 6
	m._play_rest_exit_clip()
	exit_len = m.boy.prop_clip_length()
	for pair in [[0.2, "exit_0"], [exit_len * 0.45, "exit_mid"], [exit_len - 0.05, "exit_end"]]:
		await _hold_clip(m, float(pair[0]))
		var hips3: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		_game_cam_rest(m)
		for _r in 3:
			m._apply_camera()
			await process_frame
		await _shot(vp, "%s/%s/%s_game.png" % [OUT, tag, pair[1]])
		_cam(m, hips3 + Vector3(0, 0.25, 0), yaw_front, 3.0, 0.14)
		for _r in 4:
			m._apply_camera()
			await process_frame
		await _shot(vp, "%s/%s/%s_front.png" % [OUT, tag, pair[1]])
		_cam(m, hips3 + Vector3(0, 0.22, 0), yaw_side, 2.55, 0.10)
		for _r in 4:
			m._apply_camera()
			await process_frame
		imgs.append(await _shot(vp, "%s/%s/%s_side.png" % [OUT, tag, pair[1]]))

	_montage_imgs(imgs, "%s_sit_sequence.png" % tag if tag != "bench" else "bench_sit_transition.png")
	if tag == "log":
		_montage_imgs(imgs, "log_sit.png")
	m._finish_rest_exit()


func _hammock_seq(m, vp) -> void:
	m.rest_frozen = false
	m._begin_rest("sleep")
	if not m.rest_use_clips:
		push_error("expected hammock clip rest")
		return
	m.rest_frozen = true
	m.rest_phase = 1
	m._play_rest_enter_clip()
	# Look along prop +Z (inland) — +X is the span; end-on makes cloth a thin line.
	var side: Vector3 = m.rest_prop_xf.basis.z.normalized()
	var side_yaw: float = atan2(side.x, side.z)
	var enter_len: float = m.boy.prop_clip_length()
	var imgs: Array = []

	# Enter: dense samples especially during leg-swing 2.9–5.6 s
	var enter_times := [0.2, 1.5, 2.9, 3.6, 4.4, 5.2, 5.6, enter_len * 0.85, enter_len - 0.05]
	var enter_labels := ["enter_0", "enter_1", "swing_29", "swing_36", "swing_44", "swing_52", "swing_56", "enter_lie", "enter_end"]
	for i in enter_times.size():
		await _hold_clip(m, enter_times[i])
		var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		var look_h: Vector3 = m.rest_prop_xf.origin + m.rest_prop_xf.basis * Vector3(0.0, -0.35, 0.0)
		_game_cam_rest(m)
		for _r in 3:
			m._apply_camera()
			await process_frame
		await _shot(vp, "%s/hammock/%s_game.png" % [OUT, enter_labels[i]])
		_cam(m, look_h, side_yaw, 3.2, 0.22)
		for _r in 4:
			m._apply_camera()
			await process_frame
		var img = await _shot(vp, "%s/hammock/%s_side.png" % [OUT, enter_labels[i]])
		if i in [0, 2, 4, 6, 8]:
			imgs.append(img)

	# Sleep loop
	m.rest_phase = 4
	m._play_rest_idle_clip()
	for tsec in [0.4, 3.0, 6.0]:
		await _hold_clip(m, tsec)
		m.boy.set_face_expr("sleep")
		m.boy.expr = "sleep"
		m.boy._apply_face_pack("sleep")
		var hips2: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		var head_b: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
		var look_h2: Vector3 = m.rest_prop_xf.origin + m.rest_prop_xf.basis * Vector3(0.0, -0.35, 0.0)
		_game_cam_rest(m)
		for _r in 3:
			m._apply_camera()
			await process_frame
		await _shot(vp, "%s/hammock/sleep_%.0f_game.png" % [OUT, tsec * 10.0])
		_cam(m, look_h2, side_yaw, 3.2, 0.22)
		for _r in 5:
			m._apply_camera()
			await process_frame
		imgs.append(await _shot(vp, "%s/hammock/sleep_%.0f_side.png" % [OUT, tsec * 10.0]))
		# Sleep face close
		_cam(m, head_b, side_yaw + 0.2, 0.95, deg_to_rad(50.0))
		for _r in 5:
			m._apply_camera()
			await process_frame
		await _shot(vp, "%s/hammock/sleep_%.0f_face.png" % [OUT, tsec * 10.0])

	# Exit — dense samples in leg-swing 0.9–2.4 s
	m.rest_phase = 6
	m._play_rest_exit_clip()
	var exit_len: float = m.boy.prop_clip_length()
	var exit_times := [0.15, 0.9, 1.4, 1.9, 2.4, exit_len * 0.7, exit_len - 0.05]
	var exit_labels := ["exit_0", "swing_09", "swing_14", "swing_19", "swing_24", "exit_stand", "exit_end"]
	for i in exit_times.size():
		await _hold_clip(m, exit_times[i])
		var hips3: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
		var look_h3: Vector3 = m.rest_prop_xf.origin + m.rest_prop_xf.basis * Vector3(0.0, -0.35, 0.0)
		_game_cam_rest(m)
		for _r in 3:
			m._apply_camera()
			await process_frame
		await _shot(vp, "%s/hammock/%s_game.png" % [OUT, exit_labels[i]])
		_cam(m, look_h3, side_yaw, 3.2, 0.22)
		for _r in 4:
			m._apply_camera()
			await process_frame
		var img2 = await _shot(vp, "%s/hammock/%s_side.png" % [OUT, exit_labels[i]])
		if i in [0, 1, 4, 6]:
			imgs.append(img2)

	_montage_imgs(imgs, "hammock_sequence.png")
	m._finish_rest_exit()


func _faces(m, vp) -> void:
	m.mode = m.Mode.EXPLORE
	m.rest_use_clips = false
	m._place(Vector3(2.0, 0, -6.5), 0.0)
	m.face_yaw = 0.0
	m.boy.rotation = Vector3.ZERO
	m.boy.end_prop_clip(0.0)
	m.boy.set_idle()
	m.boy.end_activity()
	var face_imgs: Array = []
	for expr in ["idle", "smile", "cheer", "sleep"]:
		m.boy.react_kind = ""
		m.boy.act_kind = ""
		m.boy.act_lie_k = 0.0
		m.boy.set_face_expr(expr)
		for _i in 12:
			m.boy.expr = expr
			m.boy._apply_face_pack(expr)
			await process_frame
		m.boy.bake_pose_mesh()
		var head: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
		_cam(m, head + Vector3(0, 0.02, 0), PI + 0.02, 0.62, -0.04)
		for _r in 6:
			m._apply_camera()
			await process_frame
		face_imgs.append(await _shot(vp, "%s/faces/%s.png" % [OUT, expr]))
		await _shot(vp, "%s/crops/face_%s_near.png" % [OUT, expr])
		_cam(m, head + Vector3(0, 0.02, 0), PI + 0.55, 0.70, -0.03)
		for _r in 5:
			m._apply_camera()
			await process_frame
		await _shot(vp, "%s/crops/face_%s_34.png" % [OUT, expr])
		m.boy.restore_pose_mesh()
	_montage_imgs(face_imgs, "faces_montage.png")
	_montage_faces_vs_refs()


func _camera_zoom(m, vp) -> void:
	m.mode = m.Mode.EXPLORE
	m._place(Vector3(4.0, 0, -5.5), -0.4)
	m.face_yaw = -0.4
	m.boy.rotation.y = -0.4
	m.boy.set_idle()
	for _i in 8:
		await process_frame
	var look: Vector3 = m.player.global_position + Vector3(0, 0.75, 0)
	var yaw: float = m.face_yaw + PI + 0.4
	var imgs: Array = []
	for pair in [["near", 2.6], ["mid", 7.0], ["far", 16.0]]:
		_cam(m, look, yaw, float(pair[1]), 0.18)
		for _r in 8:
			m.cam_dist = float(pair[1])
			m.view_dist = float(pair[1])
			m._apply_camera()
			await process_frame
		imgs.append(await _shot(vp, "%s/camera/%s.png" % [OUT, pair[0]]))
	_montage_imgs(imgs, "camera_zoom.png")


func _scenes(m, vp) -> void:
	m.mode = m.Mode.EXPLORE
	m._place(Vector3(1.5, 0, -4.0), -0.2)
	m.boy.set_idle()
	var imgs: Array = []
	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 70:
			await process_frame
	m.night_k = 0.0
	m._update_night(0.0, true)
	m.sun.rotation_degrees = Vector3(-42, 35, 0)
	m.sun.light_color = Color(1.0, 0.95, 0.85)
	m.sun.light_energy = 1.25
	for _i in 20:
		await process_frame
	_cam(m, Vector3(0, 1.2, -2), -0.8, 14.0, 0.28)
	for _r in 6:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/scene/day.png" % OUT))

	m.sun.rotation_degrees = Vector3(-12, 50, 0)
	m.sun.light_color = Color(1.0, 0.45, 0.22)
	m.sun.light_energy = 1.35
	if m.env:
		m.env.tonemap_exposure = 1.1
		m.env.fog_light_color = Color(1.0, 0.5, 0.3)
	for _i in 18:
		await process_frame
	_cam(m, Vector3(3.5, 0.9, -1.5), -1.35, 11.0, 0.12)
	for _r in 6:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/scene/sunset.png" % OUT))

	if not m.night_on:
		m.night_btn.pressed.emit()
	for _i in 100:
		await process_frame
	_cam(m, Vector3(0, 1.2, -2), -0.8, 14.0, 0.28)
	for _r in 6:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/scene/night.png" % OUT))
	_montage_imgs(imgs, "scene_day_sunset_night.png")


func _montage_faces_vs_refs() -> void:
	var ref_front := Image.load_from_file("%s/crops/expr_ref_front.png" % OUT)
	var ref_34 := Image.load_from_file("%s/crops/expr_ref_34.png" % OUT)
	if ref_front == null or ref_34 == null:
		push_warning("missing expr_ref_*.png — skip faces_vs_ref montages")
		return
	if ref_front.get_format() != Image.FORMAT_RGBA8:
		ref_front.convert(Image.FORMAT_RGBA8)
	if ref_34.get_format() != Image.FORMAT_RGBA8:
		ref_34.convert(Image.FORMAT_RGBA8)
	for tag_pair in [["front", ref_front, ""], ["34", ref_34, "_34"]]:
		var tag: String = tag_pair[0]
		var ref: Image = tag_pair[1]
		var suffix: String = tag_pair[2]
		var cell_w := 390
		var cell_h := 844
		var panel := cell_w
		var ref_row := Image.create(panel * 4, panel, false, Image.FORMAT_RGBA8)
		for i in 4:
			var src := ref.get_region(Rect2i(i * 1000, 0, 1000, 1000))
			if src.get_format() != Image.FORMAT_RGBA8:
				src.convert(Image.FORMAT_RGBA8)
			src.resize(panel, panel, Image.INTERPOLATE_LANCZOS)
			ref_row.blit_rect(src, Rect2i(0, 0, panel, panel), Vector2i(i * panel, 0))
		var game_row := Image.create(panel * 4, cell_h, false, Image.FORMAT_RGBA8)
		var names := ["idle", "smile", "cheer", "sleep"]
		for i in 4:
			var path := "%s/crops/face_%s%s_near.png" % [OUT, names[i], suffix]
			if suffix == "_34":
				path = "%s/crops/face_%s_34.png" % [OUT, names[i]]
			var g := Image.load_from_file(path)
			if g == null:
				continue
			if g.get_format() != Image.FORMAT_RGBA8:
				g.convert(Image.FORMAT_RGBA8)
			game_row.blit_rect(g, Rect2i(0, 0, mini(panel, g.get_width()), mini(cell_h, g.get_height())), Vector2i(i * panel, 0))
		var out := Image.create(panel * 4, panel + cell_h, false, Image.FORMAT_RGBA8)
		out.fill(Color(0.08, 0.09, 0.10, 1))
		out.blit_rect(ref_row, Rect2i(0, 0, panel * 4, panel), Vector2i(0, 0))
		out.blit_rect(game_row, Rect2i(0, 0, panel * 4, cell_h), Vector2i(0, panel))
		out.save_png("%s/faces_vs_ref_%s.png" % [OUT, tag])
		print("MONTAGE faces_vs_ref_%s.png" % tag)
