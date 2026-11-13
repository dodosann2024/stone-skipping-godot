extends SceneTree
## Recapture sit/sleep stills with the new face-forward rest camera.
## Writes 04/05/06 idle + mid-enter extras, then rebuilds final_montage.png.
## Leaves 01–03 and 07–09 untouched.

const OUT := "/workspace/screenshots/v25/final"
const W := 390
const H := 844


func _initialize() -> void:
	call_deferred("g")


func g() -> void:
	DisplayServer.window_set_size(Vector2i(W, H))
	var vp := get_root().get_viewport()
	vp.size = Vector2i(W, H)
	var m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 80:
		await process_frame
	if m.start_overlay and is_instance_valid(m.start_overlay):
		m.start_overlay.queue_free()
		m.start_overlay = null
	m.demo_mode = false
	m.demo_cam = false
	m.cam_fixed = false
	if m.night_on:
		m.night_btn.pressed.emit()
		for _i in 70:
			await process_frame
	m.night_k = 0.0
	m._update_night(0.0, true)
	m.sun.rotation_degrees = Vector3(-42, 48, 0)
	m.sun.light_color = Color(1.0, 0.96, 0.88)
	m.sun.light_energy = 1.35
	if m.env:
		m.env.tonemap_exposure = 1.05
		m.env.fog_light_color = Color(0.75, 0.85, 0.95)

	# ── Bench ──
	await _capture_seat(m, vp, "长椅", "04_bench_sit.png", "04_bench_enter_mid.png")
	# ── Log ──
	await _capture_seat(m, vp, "坐木", "05_log_sit.png", "05_log_enter_mid.png")
	# ── Hammock ──
	await _capture_hammock(m, vp)

	_rebuild_montage()
	print("REST_CAM_SHOTS_DONE")
	quit(0)


func _pick_seat(m, seat_name: String) -> int:
	var bi := 0
	var best_d := -1.0
	for i in m.island.seats.size():
		var st: Dictionary = m.island.seats[i]
		if String(st["name"]) != seat_name:
			continue
		if seat_name == "坐木":
			var d: float = (st["top"] as Vector3).distance_to(m.island.campfire_pos)
			if d > best_d:
				best_d = d
				bi = i
		else:
			return i
	return bi


func _settle_rest_cam(m) -> void:
	m.rest_cam_yaw = INF
	m.rest_cam_ease = 0.0
	m.demo_cam = false
	m.cam_fixed = false
	m._update_ui()
	for _i in 45:
		await process_frame


func _capture_seat(m, vp, seat_name: String, idle_name: String, mid_name: String) -> void:
	var bi := _pick_seat(m, seat_name)
	var st: Dictionary = m.island.seats[bi]
	m.seat_i = bi
	m.seat_ap = st["approach"]
	m.seat_face = st["face"]
	m.mode = m.Mode.EXPLORE
	m._place(st["approach"], atan2(-(st["face"] as Vector3).x, -(st["face"] as Vector3).z))
	for _i in 8:
		await process_frame
	m._begin_rest("seat")
	# Mid-enter: play enter clip, freeze halfway, settle framing, shoot.
	m.rest_frozen = true
	m.rest_phase = 1
	m._play_rest_enter_clip()
	m.boy.seek_prop_clip(1.1)
	m.boy._tick(0.0)
	await _settle_rest_cam(m)
	await _shot(vp, mid_name)
	print("CAM ", mid_name, " yaw=", m.cam_yaw, " pitch=", m.cam_pitch, " dist=", m.cam_dist,
		" head_ok=", not m._rest_los_blocked(m.camera.global_position, m.boy.lie_bone_world("mixamorig_Head")))
	# Idle
	m.rest_phase = 4
	m._play_rest_idle_clip()
	m.boy.seek_prop_clip(2.5)
	m.boy._tick(0.0)
	await _settle_rest_cam(m)
	await _shot(vp, idle_name)
	print("CAM ", idle_name, " yaw=", m.cam_yaw, " pitch=", m.cam_pitch, " dist=", m.cam_dist,
		" head_ok=", not m._rest_los_blocked(m.camera.global_position, m.boy.lie_bone_world("mixamorig_Head")))
	m._finish_rest_exit()
	for _i in 25:
		await process_frame


func _capture_hammock(m, vp) -> void:
	m.mode = m.Mode.EXPLORE
	m._begin_rest("sleep")
	m.rest_frozen = true
	m.rest_phase = 1
	m._play_rest_enter_clip()
	m.boy.seek_prop_clip(1.4)
	m._sync_hammock_cloth_to_boy()
	m.boy._tick(0.0)
	await _settle_rest_cam(m)
	await _shot(vp, "06_hammock_enter_mid.png")
	print("CAM hammock_enter yaw=", m.cam_yaw, " pitch=", m.cam_pitch, " dist=", m.cam_dist)
	m.rest_phase = 4
	m._play_rest_idle_clip()
	m.boy.seek_prop_clip(3.0)
	m._sync_hammock_cloth_to_boy()
	m.boy.set_face_expr("sleep")
	m.boy.expr = "sleep"
	m.boy._apply_face_pack("sleep")
	m.boy._tick(0.0)
	await _settle_rest_cam(m)
	await _shot(vp, "06_hammock_sleep.png")
	print("CAM hammock_sleep yaw=", m.cam_yaw, " pitch=", m.cam_pitch, " dist=", m.cam_dist,
		" head_ok=", not m._rest_los_blocked(m.camera.global_position, m.boy.lie_bone_world("mixamorig_Head")))
	m._finish_rest_exit()
	for _i in 25:
		await process_frame


func _shot(vp, name: String) -> void:
	var img: Image = vp.get_texture().get_image()
	if img == null:
		push_error("null shot " + name)
		return
	img.set_pixel(0, 0, Color(0.91, 0.12, 0.74, 1.0))
	img.set_pixel(1, 0, Color(0.12, 0.91, 0.55, 1.0))
	img.set_pixel(0, 1, Color(0.95, 0.85, 0.10, 1.0))
	var path := "%s/%s" % [OUT, name]
	img.save_png(path)
	print("SHOT ", path, " ", img.get_width(), "x", img.get_height())


func _rebuild_montage() -> void:
	var names := [
		"01_overview_day.png", "02_dock_throw.png", "03_walk_path.png",
		"04_bench_sit.png", "05_log_sit.png", "06_hammock_sleep.png",
		"07_overview_sunset.png", "08_overview_night.png", "09_face_smile.png",
	]
	var strip := Image.create(W * 9, H, false, Image.FORMAT_RGBA8)
	for i in 9:
		var im := Image.load_from_file("%s/%s" % [OUT, names[i]])
		if im == null:
			push_error("missing montage tile " + names[i])
			continue
		if im.get_format() != Image.FORMAT_RGBA8:
			im.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(im, Rect2i(0, 0, W, H), Vector2i(i * W, 0))
	strip.save_png("%s/final_montage.png" % OUT)
	print("MONTAGE_OK")
