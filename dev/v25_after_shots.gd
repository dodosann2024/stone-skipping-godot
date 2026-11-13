extends SceneTree
## v25 after-fix captures at 390×844 — MUST show player-visible P0 fixes.
## Writes screenshots/v25/after/ + stamps BUILD_ID so we can prove freshness vs audit.

const OUT := "/workspace/screenshots/v25/after"
const W := 390
const H := 844
const BUILD_ID := "v25-fix6"


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

	print("V25_AFTER_BUILD ", BUILD_ID, " face_decal=", m.boy._face_decal != null)
	await _gait_seq(m, vp, "walk", 1.15, 0.0)
	await _gait_seq(m, vp, "run", 2.2, 1.0)
	await _bench_transition(m, vp)
	await _log_sit(m, vp)
	await _hammock_seq(m, vp)
	await _faces(m, vp)
	await _camera_zoom(m, vp)
	await _scenes(m, vp)
	_write_crops()
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
	# Stamp a 1-pixel BUILD marker in the top-left so after≠audit even on still scenes.
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
	for i in m.island.seats.size():
		if String(m.island.seats[i]["name"]) == want_name:
			return i
	return 0


func _bench_transition(m, vp) -> void:
	var bi: int = _pick_seat(m, "长椅")
	var st: Dictionary = m.island.seats[bi]
	var face: Vector3 = st["face"].normalized()
	m.seat_i = bi
	m.seat_ap = st["approach"]
	m.seat_face = face
	m.rest_frozen = false
	m._begin_rest("seat")
	m.rest_frozen = true
	var imgs: Array = []

	# start — standing on approach, facing the seat
	m.rest_phase = 0
	m.rest_t = 0.0
	m.player.global_position = m.rest_approach
	m.boy.global_position = m.rest_approach
	m.boy.set_idle()
	m.boy.end_activity()
	m.boy.rotation.y = atan2(-face.x, -face.z)
	for _i in 6:
		await process_frame
	# Camera from the SEA looking at his face (offset ≈ face).
	var yaw_front: float = atan2(face.x, face.z)
	_cam(m, m.rest_seat + Vector3(0, 0.55, 0), yaw_front, 3.2, 0.15)
	for _r in 5:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/bench/start.png" % OUT))

	# mid — lowering
	m.rest_phase = 1
	for _p in 12:
		var pl: Vector3 = m.boy.activity("seat", 0.45, 0.0, m.gt)
		m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		await process_frame
	m.boy.bake_pose_mesh()
	_cam(m, m.rest_seat + Vector3(0, 0.5, 0), yaw_front + 0.15, 3.0, 0.18)
	for _r in 5:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/bench/mid.png" % OUT))
	m.boy.restore_pose_mesh()

	# end — full sit, feet planted, facing out
	m.rest_phase = 2
	for _p in 22:
		var pl2: Vector3 = m.boy.activity("seat", 1.0, 0.0, m.gt)
		m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl2
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._snap_sit_contact()
		await process_frame
	m.boy.bake_pose_mesh()
	var hips: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
	_cam(m, hips + Vector3(0, 0.2, 0), yaw_front + 0.2, 2.85, 0.12)
	for _r in 6:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/bench/end.png" % OUT))
	# Side corroboration crop source
	var side: Vector3 = face.cross(Vector3.UP).normalized()
	_cam(m, hips + Vector3(0, 0.15, 0), atan2(-side.x, -side.z), 3.0, 0.1)
	for _r in 4:
		m._apply_camera()
		await process_frame
	await _shot(vp, "%s/crops/bench_end_side.png" % OUT)
	m.boy.restore_pose_mesh()
	_montage_imgs(imgs, "bench_sit_transition.png")
	if m.has_method("_wake"):
		m._wake()


func _log_sit(m, vp) -> void:
	var li: int = _pick_seat(m, "坐木")
	var st: Dictionary = m.island.seats[li]
	m.seat_i = li
	m.seat_ap = st["approach"]
	m.seat_face = st["face"]
	m.rest_frozen = false
	m._begin_rest("seat")
	m.rest_frozen = true
	m.rest_phase = 2
	for _p in 20:
		var pl: Vector3 = m.boy.activity("seat", 1.0, 0.0, m.gt)
		m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._snap_sit_contact()
		await process_frame
	m.boy.bake_pose_mesh()
	var face: Vector3 = st["face"].normalized()
	var imgs: Array = []
	_cam(m, m.rest_seat + Vector3(0, 0.5, 0), atan2(face.x, face.z) + 0.25, 3.0, 0.12)
	for _r in 5:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/log/sit.png" % OUT))
	var side: Vector3 = face.cross(Vector3.UP).normalized()
	_cam(m, m.rest_seat + Vector3(0, 0.45, 0), atan2(-side.x, -side.z), 2.8, 0.1)
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
	_cam(m, m.rest_approach + Vector3(0, 0.6, 0), atan2(-side.x, -side.z) + 0.35, 3.1, 0.1)
	for _r in 4:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/hammock/enter.png" % OUT))

	# climb mid — knee up onto the lip, hands on fabric (must read as climbing, not standing)
	for _p in 14:
		m.boy.apply_hammock_climb(1.0)
		var pl: Vector3 = m.boy._live_pelvis()
		var climb_pos: Vector3 = m.rest_approach.lerp(m.rest_seat, 0.72)
		climb_pos.y = lerpf(m.rest_approach.y, m.rest_seat.y, 0.72) + 0.16
		m.boy.global_transform = Transform3D(m.rest_sit_b, climb_pos - m.rest_sit_b * pl)
		m._update_hammock_load()
		await process_frame
	m.boy.bake_pose_mesh()
	# Side view so the hiked knee + lean into fabric read as a climb (not a rear stand).
	var climb_yaw: float = atan2(side.x, side.z) + 0.55
	_cam(m, m.rest_seat + Vector3(0, 0.45, 0), climb_yaw, 2.7, 0.12)
	for _r in 5:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/hammock/climb_mid.png" % OUT))
	m.boy.restore_pose_mesh()

	# sit on edge
	m.rest_phase = 2
	for _p in 18:
		var pl2: Vector3 = m.boy.activity("sleep", 1.0, 0.0, m.gt)
		m.rest_root_sit = m.rest_seat - m.rest_sit_b * pl2
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._snap_sit_contact()
		m._update_hammock_load()
		await process_frame
	m.boy.bake_pose_mesh()
	_cam(m, m.rest_seat + Vector3(0, 0.5, 0), atan2(-side.x, -side.z) + 0.15, 2.85, 0.18)
	for _r in 4:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/hammock/sit.png" % OUT))
	m.boy.restore_pose_mesh()

	# lying — settle hard against mesh penet
	m.rest_phase = 4
	m.set_meta("lie_snapped", false)
	m.boy.set_face_expr("sleep")
	for _p in 36:
		var pl3: Vector3 = m.boy.activity("sleep", 1.0, 1.0, m.gt)
		var swing = m.island.swing_hammock(0.0)
		m.boy.global_transform = swing * Transform3D(m.rest_lie_b, m.rest_lie - m.rest_lie_b * pl3)
		m._update_hammock_load()
		m._snap_lie_contact()
		m.boy._update_face(0.05)
		await process_frame
	m.set_meta("lie_snapped", true)
	for _i in 10:
		m.boy._update_face(0.1)
		await process_frame
	m.boy.bake_pose_mesh()
	var hips2: Vector3 = m.boy.lie_bone_world("mixamorig_Hips")
	var head_b: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
	_cam(m, hips2.lerp(head_b, 0.45), atan2(side.x, side.z) + 0.25, 2.5, 0.32)
	for _r in 6:
		m._apply_camera()
		await process_frame
	imgs.append(await _shot(vp, "%s/hammock/lie.png" % OUT))
	await _shot(vp, "%s/crops/hammock_lie_crop.png" % OUT)
	# Look down at the face from the chest-sky side so sleep lids are readable.
	var face_dir: Vector3 = m.boy.model.global_transform.basis.z.normalized()
	var face_yaw: float = atan2(-face_dir.x, -face_dir.z)
	_cam(m, head_b + face_dir * 0.05, face_yaw, 0.95, -0.25)
	for _r in 6:
		m._apply_camera()
		await process_frame
	await _shot(vp, "%s/hammock/sleep_face.png" % OUT)
	await _shot(vp, "%s/faces/sleep.png" % OUT)
	m.boy.restore_pose_mesh()

	# exit mid — roll to sit
	m.rest_phase = 6
	m.boy.set_face_expr("smile")
	for _p in 12:
		m.boy.apply_hammock_climb(0.6)
		var pl4: Vector3 = m.boy._live_pelvis()
		m.boy.global_transform = Transform3D(m.rest_sit_b, m.rest_root_sit)
		m._update_hammock_load()
		await process_frame
	m.boy.bake_pose_mesh()
	_cam(m, m.rest_seat + Vector3(0, 0.55, 0), atan2(-side.x, -side.z) + 0.3, 3.0, 0.12)
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
	_cam(m, m.rest_approach + Vector3(0, 0.6, 0), atan2(-side.x, -side.z) + 0.25, 3.1, 0.1)
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
	var face_imgs: Array = []
	for expr in ["idle", "smile", "cheer"]:
		m.boy.set_face_expr(expr)
		if expr == "cheer":
			m.boy.react_kind = "cheer"
		else:
			m.boy.react_kind = ""
		for _i in 14:
			m.boy._update_face(0.08)
			await process_frame
		m.boy.bake_pose_mesh()
		var head: Vector3 = m.boy.lie_bone_world("mixamorig_Head")
		_cam(m, head, PI + 0.05, 0.92, -0.02)
		for _r in 6:
			m._apply_camera()
			await process_frame
		face_imgs.append(await _shot(vp, "%s/faces/%s.png" % [OUT, expr]))
		await _shot(vp, "%s/crops/face_%s.png" % [OUT, expr])
		m.boy.restore_pose_mesh()
	m.boy.react_kind = ""
	var sleep_img: Image = Image.load_from_file("%s/faces/sleep.png" % OUT)
	if sleep_img:
		face_imgs.append(sleep_img)
	_montage_imgs(face_imgs, "faces_montage.png")


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
	# Clearly different distances — must be obvious in the montage strip.
	for pair in [["near", 2.6], ["mid", 7.0], ["far", 16.0]]:
		_cam(m, look, yaw, float(pair[1]), 0.18)
		for _r in 8:
			m.cam_dist = float(pair[1])
			m.fix_dist = float(pair[1])
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


func _write_crops() -> void:
	# Convenience crops for the report (also written live above for key P0s).
	pass
