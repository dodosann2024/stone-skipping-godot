extends SceneTree
## v25 Step-1 audit captures at 390×844 from gameplay-like cameras.
## Produces frame sequences + montages under screenshots/v25/audit/.

const OUT := "/workspace/screenshots/v25/audit"
const W := 390
const H := 844


func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(W, H))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(W, H)
	DirAccess.make_dir_recursive_absolute(OUT)
	DirAccess.make_dir_recursive_absolute(OUT + "/walk")
	DirAccess.make_dir_recursive_absolute(OUT + "/run")
	DirAccess.make_dir_recursive_absolute(OUT + "/bench")
	DirAccess.make_dir_recursive_absolute(OUT + "/log")
	DirAccess.make_dir_recursive_absolute(OUT + "/hammock")
	DirAccess.make_dir_recursive_absolute(OUT + "/faces")
	DirAccess.make_dir_recursive_absolute(OUT + "/camera")
	DirAccess.make_dir_recursive_absolute(OUT + "/scene")

	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 55:
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

	await _gait_seq(m, vp, "walk", 1.15, 0.0)
	await _gait_seq(m, vp, "run", 2.2, 1.0)
	await _bench_transition(m, vp)
	await _log_sit(m, vp)
	await _hammock_seq(m, vp)
	await _faces(m, vp)
	await _camera_zoom(m, vp)
	await _scenes(m, vp)
	print("V25_AUDIT_SHOTS_DONE")
	quit(0)


func _follow_cam(m, look: Vector3, behind_yaw: float, dist: float, pitch: float, h: float) -> void:
	m.demo_cam = true
	m.cam_fixed = true
	m.cam_target = look + Vector3(0, h, 0)
	m.cam_yaw = behind_yaw
	m.cam_pitch = pitch
	m.cam_dist = dist
	m._apply_camera()


func _shot(vp, path: String) -> Image:
	var tex = vp.get_texture()
	if tex == null:
		push_error("null viewport texture for " + path)
		return null
	var img: Image = tex.get_image()
	if img == null:
		push_error("null image for " + path)
		return null
	img.save_png(path)
	print("SHOT ", path, " ", img.get_width(), "x", img.get_height())
	return img


func _montage_imgs(imgs: Array, out_name: String) -> void:
	var n := imgs.size()
	if n == 0:
		return
	var strip := Image.create(W * n, H, false, Image.FORMAT_RGBA8)
	for i in n:
		var img: Image = imgs[i]
		if img == null:
			continue
		strip.blit_rect(img, Rect2i(0, 0, mini(W, img.get_width()), mini(H, img.get_height())), Vector2i(i * W, 0))
	var path := "%s/%s" % [OUT, out_name]
	strip.save_png(path)
	print("MONTAGE ", path, " bytes~", strip.get_width() * strip.get_height())


func _gait_seq(m, vp, tag: String, speed: float, run_k: float) -> void:
	m.mode = m.Mode.EXPLORE
	m._place(Vector3(3.2, 0, -7.2), 0.0)
	m.face_yaw = 0.0
	m.boy.rotation = Vector3.ZERO
	m.boy.set_idle()
	m.boy.end_activity()
	for _i in 8:
		await process_frame
	m.boy.anim = "move"
	m.boy.set_move(speed)
	m.boy.move_w = 1.0
	m.boy.act_w = 0.0
	m.boy.run_k = run_k
	m.boy.pivoting = false
	m.boy.has_prev = false
	# Warm up with real distance advance so phase tracks stride.
	for _w in 18:
		var dt := 1.0 / 30.0
		m.boy.set_move(speed)
		m.boy.move_w = 1.0
		m.boy.run_k = run_k
		m.player.global_position.x += speed * dt
		m.boy.global_position = m.player.global_position
		m.boy._tick(dt)
		await process_frame
	var imgs: Array = []
	for f in 8:
		var dt2 := 1.0 / 30.0
		m.boy.set_move(speed)
		m.boy.move_w = 1.0
		m.boy.run_k = run_k
		m.player.global_position.x += speed * dt2
		m.boy.global_position = m.player.global_position
		m.boy._tick(dt2)
		m.boy.bake_pose_mesh()
		# Gameplay follow-behind 3/4 (not pure side orthographic).
		var look: Vector3 = m.player.global_position + Vector3(0, 0.55, 0)
		_follow_cam(m, look, PI + 0.55, 3.1 if tag == "walk" else 3.4, 0.12, 0.0)
		for _r in 3:
			m._apply_camera()
			await process_frame
		var nm := "f%02d" % f
		var im := await _shot(vp, "%s/%s/%s.png" % [OUT, tag, nm])
		imgs.append(im)
		m.boy.restore_pose_mesh()
	_montage_imgs(imgs, "%s_8frame.png" % tag)


func _pick_seat(m, want_name: String) -> int:
	for i in m.island.seats.size():
		if String(m.island.seats[i]["name"]) == want_name:
			return i
	return 0


func _arm_seat(m, i: int) -> void:
	var st: Dictionary = m.island.seats[i]
	m.seat_i = i
	m.seat_ap = st["approach"]
	m.seat_face = st["face"]
	m.player.global_position = st["approach"]
	m.boy.global_position = st["approach"]
	m.face_yaw = atan2(-st["face"].x, -st["face"].z)


func _bench_transition(m, vp) -> void:
	var bi := _pick_seat(m, "长椅")
	_arm_seat(m, bi)
	m.rest_frozen = false
	m._begin_rest("seat")
	m.rest_frozen = true
	var imgs: Array = []
	# start: approach standing
	m.rest_phase = 0
	m.rest_t = 0.0
	m.player.global_position = m.rest_approach
	m.boy.global_position = m.rest_approach
	m.boy.set_idle()
	m.boy.end_activity()
	for _i in 6:
		await process_frame
	var look0: Vector3 = m.rest_seat + Vector3(0, 0.55, 0)
	_follow_cam(m, look0, atan2(-m.rest_side.x, -m.rest_side.z) + 0.35, 3.2, 0.18, 0.0)
	for _r in 4:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/bench/start.png" % OUT))

	# mid: sit_k ~0.45
	m.rest_phase = 1
	for _p in 10:
		var pl = m.boy.activity("seat", 0.45, 0.0, m.gt)
		m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		await process_frame
	m.boy.bake_pose_mesh()
	_follow_cam(m, m.rest_seat + Vector3(0, 0.5, 0), atan2(-m.rest_side.x, -m.rest_side.z) + 0.2, 3.0, 0.2, 0.0)
	for _r in 4:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/bench/mid.png" % OUT))
	m.boy.restore_pose_mesh()

	# end: full sit
	m.rest_phase = 2
	for _p in 18:
		var pl2 = m.boy.activity("seat", 1.0, 0.0, m.gt)
		m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl2
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._snap_sit_contact()
		await process_frame
	m.boy.bake_pose_mesh()
	_follow_cam(m, m.rest_seat + Vector3(0, 0.48, 0), atan2(-m.rest_side.x, -m.rest_side.z), 2.9, 0.22, 0.0)
	for _r in 4:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/bench/end.png" % OUT))
	m.boy.restore_pose_mesh()
	_montage_imgs(imgs, "bench_sit_transition.png")
	if m.has_method("_wake"):
		m._wake()


func _log_sit(m, vp) -> void:
	var li := _pick_seat(m, "坐木")
	_arm_seat(m, li)
	m.rest_frozen = false
	m._begin_rest("seat")
	m.rest_frozen = true
	m.rest_phase = 2
	for _p in 20:
		var pl = m.boy.activity("seat", 1.0, 0.0, m.gt)
		m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._snap_sit_contact()
		await process_frame
	m.boy.bake_pose_mesh()
	var imgs: Array = []
	_follow_cam(m, m.rest_seat + Vector3(0, 0.5, 0), atan2(-m.rest_side.x, -m.rest_side.z) + 0.4, 3.1, 0.15, 0.0)
	for _r in 5:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/log/sit.png" % OUT))
	_follow_cam(m, m.rest_seat + Vector3(0, 0.45, 0), atan2(-m.rest_side.x, -m.rest_side.z) + PI * 0.5, 2.8, 0.1, 0.0)
	for _r in 4:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/log/sit_side.png" % OUT))
	m.boy.restore_pose_mesh()
	_montage_imgs(imgs, "log_sit.png")
	if m.has_method("_wake"):
		m._wake()


func _hammock_seq(m, vp) -> void:
	m.rest_frozen = false
	m._begin_rest("sleep")
	m.rest_frozen = true
	var along: Vector3 = (m.island.hammock_b - m.island.hammock_a).normalized()
	var side: Vector3 = m.rest_side.normalized()
	var imgs: Array = []

	# enter stand
	m.rest_phase = 0
	m.player.global_position = m.rest_approach
	m.boy.global_position = m.rest_approach
	m.boy.rotation = Vector3(0, atan2(-side.x, -side.z), 0)
	m.boy.set_idle()
	m.boy.end_activity()
	m.island.set_hammock_load([] as Array[Vector3])
	for _i in 6:
		await process_frame
	_follow_cam(m, m.rest_approach + Vector3(0, 0.6, 0), atan2(-side.x, -side.z) + 0.3, 3.0, 0.12, 0.0)
	for _r in 4:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/hammock/enter.png" % OUT))

	# mid climb (sit_k 0.5)
	for _p in 8:
		var pl = m.boy.activity("sleep", 0.5, 0.0, m.gt)
		m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._update_hammock_load()
		await process_frame
	m.boy.bake_pose_mesh()
	_follow_cam(m, m.rest_seat + Vector3(0, 0.55, 0), atan2(-side.x, -side.z) + 0.25, 2.9, 0.18, 0.0)
	for _r in 4:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/hammock/climb_mid.png" % OUT))
	m.boy.restore_pose_mesh()

	# sit on edge
	m.rest_phase = 2
	for _p in 16:
		var pl2 = m.boy.activity("sleep", 1.0, 0.0, m.gt)
		m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl2
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._snap_sit_contact()
		m._update_hammock_load()
		await process_frame
	m.boy.bake_pose_mesh()
	_follow_cam(m, m.rest_seat + Vector3(0, 0.5, 0), atan2(-side.x, -side.z), 2.85, 0.2, 0.0)
	for _r in 4:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/hammock/sit.png" % OUT))
	m.boy.restore_pose_mesh()

	# lying
	m.rest_phase = 4
	m.set_meta("lie_snapped", false)
	for _p in 28:
		var pl3 = m.boy.activity("sleep", 1.0, 1.0, m.gt)
		var swing = m.island.swing_hammock(0.0)
		m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl3)
		m._update_hammock_load()
		m._snap_lie_contact()
		m.boy._update_face(0.05)
		await process_frame
	m.set_meta("lie_snapped", true)
	m.boy.set_face_expr("sleep")
	for _i in 8:
		m.boy._update_face(0.1)
		await process_frame
	m.boy.bake_pose_mesh()
	var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
	var head_b: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
	var hold_look: Vector3 = hips.lerp(head_b, 0.4)
	_follow_cam(m, hold_look, atan2(side.x, side.z) + 0.2, 2.6, 0.35, 0.0)
	for _r in 5:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/hammock/lie.png" % OUT))
	# sleep face close-up
	_follow_cam(m, head_b, atan2(side.x, side.z) + 0.15, 1.15, 0.25, 0.0)
	for _r in 5:
		m._apply_camera()
		await process_frame
	await _shot(vp, "%s/hammock/sleep_face.png" % OUT)
	await _shot(vp, "%s/faces/sleep.png" % OUT)
	m.boy.restore_pose_mesh()

	# exit mid
	m.rest_phase = 6
	m.boy.set_face_expr("smile")
	for _p in 12:
		m.boy.activity("sleep", 0.55, 0.0, m.gt)
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._update_hammock_load()
		await process_frame
	m.boy.bake_pose_mesh()
	_follow_cam(m, m.rest_seat + Vector3(0, 0.55, 0), atan2(-side.x, -side.z) + 0.3, 3.0, 0.15, 0.0)
	for _r in 4:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/hammock/exit_mid.png" % OUT))
	m.boy.restore_pose_mesh()

	# exit stand
	m.rest_phase = 7
	m.player.global_position = m.rest_approach
	m.boy.global_position = m.rest_approach
	m.boy.set_idle()
	m.boy.end_activity()
	m.island.set_hammock_load([] as Array[Vector3])
	for _i in 6:
		await process_frame
	_follow_cam(m, m.rest_approach + Vector3(0, 0.6, 0), atan2(-side.x, -side.z) + 0.25, 3.1, 0.1, 0.0)
	for _r in 4:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/hammock/exit.png" % OUT))
	_montage_imgs(imgs, "hammock_sequence.png")
	if m.has_method("_wake"):
		m._wake()


func _faces(m, vp) -> void:
	m.mode = m.Mode.EXPLORE
	m._place(Vector3(2.0, 0, -6.5), 0.0)
	m.face_yaw = 0.0
	m.boy.rotation = Vector3.ZERO
	m.boy.set_idle()
	m.boy.end_activity()
	m.island.visible = true
	var face_imgs: Array = []
	# idle first
	m.boy.set_face_expr("smile")
	m.boy.end_activity()
	for _i in 8:
		m.boy._update_face(0.08)
		await process_frame
	m.boy.bake_pose_mesh()
	var head0: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
	_follow_cam(m, head0, PI + 0.35, 1.05, 0.0, 0.0)
	for _r in 5:
		m._apply_camera()
		await process_frame
	face_imgs.append(await _shot(vp, "%s/faces/idle.png" % OUT))
	m.boy.restore_pose_mesh()

	for expr in ["smile", "cheer"]:
		m.boy.set_face_expr(expr)
		if expr == "cheer" and m.boy.has_method("do_cheer"):
			m.boy.do_cheer()
		elif expr == "cheer":
			m.boy.set_face_expr("cheer")
		for _i in 12:
			m.boy._update_face(0.08)
			await process_frame
		m.boy.bake_pose_mesh()
		var head: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
		_follow_cam(m, head, PI + 0.15, 0.95, -0.05, 0.0)
		for _r in 5:
			m._apply_camera()
			await process_frame
		face_imgs.append(await _shot(vp, "%s/faces/%s.png" % [OUT, expr]))
		m.boy.restore_pose_mesh()
	# sleep already captured; reload into montage if present
	var sleep_img := Image.load_from_file("%s/faces/sleep.png" % OUT)
	if sleep_img:
		face_imgs.append(sleep_img)
	_montage_imgs(face_imgs, "faces_montage.png")


func _camera_zoom(m, vp) -> void:
	m.mode = m.Mode.EXPLORE
	m._place(Vector3(4.0, 0, -5.5), -0.4)
	m.face_yaw = -0.4
	m.boy.rotation.y = -0.4
	m.boy.set_idle()
	for _i in 6:
		await process_frame
	var look: Vector3 = m.player.global_position + Vector3(0, 0.7, 0)
	var imgs: Array = []
	for pair in [["near", 2.6], ["mid", 5.5], ["far", 12.0]]:
		_follow_cam(m, look, m.face_yaw + PI + 0.35, float(pair[1]), 0.22, 0.0)
		for _r in 5:
			m._apply_camera()
			await process_frame
		imgs.append(await _shot(vp, "%s/camera/%s.png" % [OUT, pair[0]]))
	_montage_imgs(imgs, "camera_zoom.png")


func _scenes(m, vp) -> void:
	m.mode = m.Mode.EXPLORE
	m._place(Vector3(1.5, 0, -4.0), -0.2)
	m.face_yaw = -0.2
	m.boy.rotation.y = -0.2
	m.boy.set_idle()
	var imgs: Array = []
	# Day wide
	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 70:
			await process_frame
	m.night_k = 0.0
	m._update_night(0.0, true)
	for _i in 20:
		await process_frame
	_follow_cam(m, Vector3(0, 1.2, -2), -0.8, 14.0, 0.28, 0.0)
	for _r in 6:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/scene/day.png" % OUT))

	# Sunset-ish: warm sun, lower
	m.sun.rotation_degrees = Vector3(-18, 40, 0)
	m.sun.light_color = Color(1.0, 0.55, 0.28)
	m.sun.light_energy = 1.15
	if m.env:
		m.env.tonemap_exposure = 1.05
		m.env.fog_light_color = Color(1.0, 0.55, 0.35)
	for _i in 15:
		await process_frame
	_follow_cam(m, Vector3(2, 1.0, -3), -1.1, 13.0, 0.2, 0.0)
	for _r in 6:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/scene/sunset.png" % OUT))

	# Night
	if not m.night_on:
		m.night_btn.pressed.emit()
	for _i in 90:
		await process_frame
	_follow_cam(m, Vector3(0, 1.2, -2), -0.8, 14.0, 0.28, 0.0)
	for _r in 6:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/scene/night.png" % OUT))
	_montage_imgs(imgs, "scene_day_sunset_night.png")
